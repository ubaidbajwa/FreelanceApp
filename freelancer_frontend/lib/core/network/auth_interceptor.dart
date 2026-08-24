import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/session_controller.dart';
import '../../features/auth/data/models/auth_response.dart';
import '../constants/api_constants.dart';
import '../router/app_router.dart';
import '../storage/secure_storage_service.dart';

/// Access token attach karta hai, aur 401 ko SINGLE-FLIGHT refresh se handle:
/// ek waqt mein sirf EK refresh chalti hai — saari concurrent 401 requests wahi
/// ek in-flight Future await karti hain. Ye is liye critical hai kyunke backend
/// refresh tokens ROTATE karta hai (`ValidateAndConsumeAsync` purana consume kar
/// deta, `BuildAuthResponseAsync` naya banata) — parallel refreshes ek doosre ka
/// token consume kar ke ek recoverable session tabah kar dete.
///
/// Refresh success pe original request naye access token se transparently retry
/// hoti hai; fail pe session tear-down + sign-in redirect.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._ref, this._refreshDio);

  final Ref _ref;

  // Bare client (koi AuthInterceptor NAHI) — refresh call + retry isi se jate
  // hain, taake (a) refresh khud 401 ho to dobara onError mein recurse na kare,
  // (b) retried request dobara interceptor se process na ho.
  final Dio _refreshDio;

  // Wahi ek shared refresh. `??=` guarantee deta hai: pehli 401 ise start karti
  // hai aur har concurrent 401 wahi SAME Future await karti hai; settle hote hi
  // clear ho jata hai. Dart single-threaded hai, is liye assignment aur await ke
  // beech koi race nahi.
  Future<bool>? _refreshing;

  SecureStorageService get _storage => _ref.read(secureStorageProvider);

  // Auth endpoints (refresh/login/register/google/…) pe kabhi refresh mat karo —
  // wo recurse karega, aur wahan 401 ka matlab hi hai credentials/refresh dead.
  static bool _isAuthPath(String path) => path.contains('/api/auth/');

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final is401 = err.response?.statusCode == 401;

    if (!is401 || _isAuthPath(err.requestOptions.path)) {
      // 401 ke ilawa sab, aur auth-endpoint ke 401, seedha aage — koi refresh nahi.
      return handler.next(err);
    }

    final refreshed = await _ensureRefreshed();
    if (!refreshed) {
      // Session _endSession() ke andar tear-down ho chuki (tokens clear, state
      // expired, /login pe redirect). 401 ko surface hone do — mapper us screen
      // par (jo abhi replace ho rahi hai) "session expired" dikha dega.
      return handler.next(err);
    }

    // Refresh kamyab — original request naye access token se retry karo.
    try {
      final token = await _storage.getAccessToken();
      final req = err.requestOptions;
      req.headers['Authorization'] = 'Bearer $token';
      final response = await _refreshDio.fetch(req);
      handler.resolve(response); // user ko kuch nazar nahi aata
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }

  // Single-flight ka dil: pehla caller `_doRefresh()` start karta hai, baaki wahi
  // future await karte hain; settle pe `_refreshing` null.
  Future<bool> _ensureRefreshed() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      // Koi refresh token hi nahi (ya "remember me" off tha) — recover mumkin nahi.
      await _endSession();
      return false;
    }
    try {
      final res = await _refreshDio.post(
        ApiConstants.refresh,
        data: {'refreshToken': refreshToken},
      );
      final auth = AuthResponse.fromJson(res.data as Map<String, dynamic>);
      // DONO save karo — backend ne refresh token rotate kar diya, purana ab dead
      // hai; use rakha to agli refresh toot jaati.
      await _storage.saveTokens(
        accessToken: auth.accessToken,
        refreshToken: auth.refreshToken,
      );
      return true;
    } on DioException {
      // Refresh 401/expired/revoked — session genuinely khatam.
      await _endSession();
      return false;
    }
  }

  // Unrecoverable auth failure: tokens purge (dead token dobara kabhi na jaye),
  // session flag expire, aur stack replace kar ke sign-in (go, push nahi — back
  // se toota authenticated screen wapas na aaye).
  Future<void> _endSession() async {
    await _storage.clearTokens();
    _ref.read(sessionControllerProvider.notifier).expire();
    appRouter.go('/login');
  }
}
