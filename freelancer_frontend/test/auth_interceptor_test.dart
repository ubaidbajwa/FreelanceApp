// Single-flight refresh verification. Kai parallel 401s ek hi refresh trigger
// karein (backend rotate karta hai — parallel refreshes session tabah kar dete).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer_frontend/core/network/auth_interceptor.dart';
import 'package:freelancer_frontend/core/storage/secure_storage_service.dart';
import 'package:freelancer_frontend/features/auth/application/session_controller.dart';

void main() {
  // GoRouter.go() (session tear-down mein) ko binding chahiye.
  TestWidgetsFlutterBinding.ensureInitialized();

  ({
    Dio dio,
    _FakeAdapter adapter,
    _FakeStorage storage,
    ProviderContainer container,
  }) build({bool refreshUnauthorized = false, String? refreshToken = 'old-refresh'}) {
    final storage = _FakeStorage()..refresh = refreshToken;
    final adapter = _FakeAdapter(refreshUnauthorized: refreshUnauthorized);
    final container = ProviderContainer(
      overrides: [secureStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    final refreshDio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter;
    final dio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter;

    // AuthInterceptor ko real Ref chahiye — ek provider ke andar se milta hai.
    final interceptorProvider =
        Provider((ref) => AuthInterceptor(ref, refreshDio));
    dio.interceptors.add(container.read(interceptorProvider));

    return (dio: dio, adapter: adapter, storage: storage, container: container);
  }

  test('5 concurrent 401s trigger EXACTLY ONE refresh, then all retry OK', () async {
    final h = build();

    // Paanch parallel authenticated requests — sab ek saath 401 khayengi.
    final results = await Future.wait([
      for (var i = 0; i < 5; i++) h.dio.get('/api/test'),
    ]);

    expect(h.adapter.refreshCount, 1, reason: 'single-flight: one refresh only');
    expect(results.every((r) => r.statusCode == 200), isTrue,
        reason: 'har request naye token se transparently retry hui');
    expect(h.storage.access, 'new-access');
    expect(h.storage.refresh, 'new-refresh'); // rotated token persist hua
  });

  test('POST with body + query 401s → retry replays method, body, query intact',
      () async {
    // F-M2 concern: chat message POST hai. Agar retry body kho de to send
    // silently fail ho — bubble "failed" ho jaye bina kisi asli wajah ke.
    final h = build();

    final res = await h.dio.post(
      '/api/test',
      data: {'text': 'salaam duniya', 'conversationId': 42},
      queryParameters: {'preview': 'true'},
    );

    expect(res.statusCode, 200, reason: 'refresh + retry transparent hui');
    expect(h.adapter.refreshCount, 1, reason: 'exactly ek refresh');
    expect(h.adapter.capturedMethod, 'POST',
        reason: 'HTTP method retry ke baad bhi POST');
    expect(h.adapter.capturedUri?.queryParameters['preview'], 'true',
        reason: 'query parameter retry mein survive kiya');

    final body =
        jsonDecode(h.adapter.capturedBody ?? '{}') as Map<String, dynamic>;
    expect(body['text'], 'salaam duniya', reason: 'JSON body intact');
    expect(body['conversationId'], 42, reason: 'poora payload replay hua');
  });

  test('invalid refresh token → tokens cleared + session marked expired', () async {
    final h = build(refreshUnauthorized: true);

    await expectLater(h.dio.get('/api/test'), throwsA(isA<DioException>()));

    expect(h.storage.access, isNull, reason: 'dead token dobara na jaye');
    expect(h.storage.refresh, isNull);
    expect(h.container.read(sessionControllerProvider), SessionStatus.expired);
  });

  test('no refresh token → immediate teardown, no refresh call', () async {
    final h = build(refreshToken: null);

    await expectLater(h.dio.get('/api/test'), throwsA(isA<DioException>()));

    expect(h.adapter.refreshCount, 0, reason: 'refresh token hi nahi tha');
    expect(h.storage.access, isNull);
    expect(h.container.read(sessionControllerProvider), SessionStatus.expired);
  });
}

// In-memory storage — real FlutterSecureStorage (platform channels) ko touch
// nahi karta kyunke saare methods override hain.
class _FakeStorage extends SecureStorageService {
  _FakeStorage() : super(const FlutterSecureStorage());
  String? access = 'old-access';
  String? refresh = 'old-refresh';

  @override
  Future<String?> getAccessToken() async => access;
  @override
  Future<String?> getRefreshToken() async => refresh;
  @override
  Future<void> saveTokens(
      {required String accessToken, required String refreshToken}) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> saveAccessTokenOnly(String accessToken) async =>
      access = accessToken;
  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
  }
}

// Dono dios (main + refresh) isi adapter ko share karte hain: refresh count karta
// hai, /api/test ko new-access pe 200 warna 401.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.refreshUnauthorized = false});
  final bool refreshUnauthorized;
  int refreshCount = 0;

  // Retry (successful, new-access) request ka faithful snapshot — POST body +
  // query + method retry ke baad bhi intact aaya ya nahi, ye verify karne ke liye.
  String? capturedMethod;
  Uri? capturedUri;
  String? capturedBody;

  static const _json = {
    Headers.contentTypeHeader: ['application/json'],
  };

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    // Thoda delay taake paanch requests genuinely overlap karein.
    await Future<void>.delayed(const Duration(milliseconds: 10));

    if (options.path == '/api/auth/refresh') {
      refreshCount++;
      if (refreshUnauthorized) {
        return ResponseBody.fromString(
            '{"detail":"Invalid or expired refresh token"}', 401,
            headers: _json);
      }
      final body = jsonEncode({
        'accessToken': 'new-access',
        'refreshToken': 'new-refresh',
        'tokenType': 'Bearer',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
        'user': {
          'id': 'u1',
          'email': 'a@b.com',
          'fullName': 'A B',
          'role': 'Freelancer',
          'isIdentityVerified': false,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      });
      return ResponseBody.fromString(body, 200, headers: _json);
    }

    if (options.path == '/api/test') {
      final ok = options.headers['Authorization'] == 'Bearer new-access';
      if (ok) {
        // Ye sirf retry (new-access) pe chalta hai — pehli 401 attempt skip.
        // Body adapter tak stream ban ke aati hai; Dio ne `data` Map ko dobara
        // encode kiya, is liye replay pe bhi poori milni chahiye.
        capturedMethod = options.method;
        capturedUri = options.uri;
        if (requestStream != null) {
          final bytes = await requestStream.fold<List<int>>(
              <int>[], (acc, chunk) => acc..addAll(chunk));
          capturedBody = utf8.decode(bytes);
        }
      }
      return ResponseBody.fromString(
          ok ? '{"ok":true}' : '{"detail":"expired"}', ok ? 200 : 401,
          headers: _json);
    }

    return ResponseBody.fromString('{}', 404, headers: _json);
  }

  @override
  void close({bool force = false}) {}
}
