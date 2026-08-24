// Real reCAPTCHA v2 (checkbox + image challenge) wired here — custom card pe
// tap hote hi WebView sheet khulti hai jisme Google ka asli v2 widget hota hai.
// DEV NOTE: backend has Captcha:Enabled=false bypass in Development — it does NOT
// verify the token there, so the emulator/dev flow keeps working end-to-end
// even without a real token. The token is still SENT (backend validator
// requires a non-empty CaptchaToken); only server-side verification is skipped.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/recaptcha_config.dart';
import '../../../../core/constants/user_role.dart';
import '../../application/signup_flow_notifier.dart';
import '../../data/auth_repository.dart';
import '../../data/models/register_request.dart';
import '../widgets/recaptcha_v2_sheet.dart';

class SecurityCheckScreen extends ConsumerStatefulWidget {
  const SecurityCheckScreen({super.key});

  @override
  ConsumerState<SecurityCheckScreen> createState() =>
      _SecurityCheckScreenState();
}

class _SecurityCheckScreenState extends ConsumerState<SecurityCheckScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);
  static const _red = Color(0xFFE53935);

  bool _checking = false;   // captcha token fetch (spinner in card)
  bool _checked = false;    // captcha done — gold tick
  bool _error = false;      // captcha fail — red state
  bool _registering = false; // register API chal rahi hai (card ke neeche spinner)

  Future<void> _onTapRobot() async {
    if (_checking || _checked) return; // error state pe tap = retry (allowed)

    setState(() {
      _checking = true;
      _error = false;
    });

    // Dev bypass — localhost pe WebView sheet kholne se do "I'm not a robot"
    // prompts dikhte hain (custom card + WebView). Backend Captcha:Enabled=false
    // hai to stub token bhi kaam karta hai. Production (real domain) mein asli
    // v2 checkbox chalega.
    if (RecaptchaConfig.useDevBypass) {
      // _checking already true hai (upar) — thora ruk ke spinner dikhao, phir
      // gold check. Warna dono setState batch ho ke spinner frame skip ho jata
      // aur real security-check jaisa feel nahi aata.
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() {
        _checking = false;
        _checked = true;
      });
      await _register(RecaptchaConfig.devBypassToken);
      return;
    }

    // v2 checkbox sheet — user "I'm not a robot" tick karta hai, zaroorat pe
    // image challenge solve karta hai. Token milte hi sheet khud band ho jati
    // hai; dismiss/expire/error pe null aata hai.
    final token = await showRecaptchaV2Sheet(context);

    if (!mounted) return;

    // Empty/no token → submission block, user-friendly error.
    if (token == null || token.isEmpty) {
      setState(() {
        _checking = false;
        _error = true; // red state on card
      });
      _showError('Please complete the security check');
      return;
    }

    setState(() {
      _checking = false;
      _checked = true;
    });
    await _register(token);
  }

  Future<void> _register(String captchaToken) async {
    setState(() => _registering = true);
    final data = ref.read(signupFlowProvider);
    try {
      final fullName = '${data.firstName} ${data.lastName}'.trim();
      final role = UserRole.values.firstWhere(
        (r) => r.value == data.role,
        orElse: () => UserRole.freelancer,
      );

      await ref.read(authRepositoryProvider).register(
            RegisterRequest(
              email: data.email,
              password: data.password,
              fullName: fullName,
              role: role,
              captchaToken: captchaToken,
            ),
          );

      if (!mounted) return;
      context.go('/verify-email', extra: data.email);
    } on DioException catch (e) {
      if (!mounted) return;
      final message =
          e.response?.data?['detail'] ?? 'Something went wrong. Try again.';
      _showError(message);
      // Retry allow karo — box wapas uncheck
      setState(() {
        _checked = false;
        _registering = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Text(
                "Let's do a quick security check",
                style: TextStyle(
                    color: _navy, fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 32),
              _checkCard(),
              // Register API chal rahi hai — user ko pata hona chahiye
              if (_registering) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _gold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Creating your account…',
                      style: TextStyle(
                        color: _navy.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _error ? _red : _navy.withValues(alpha: 0.12),
          width: _error ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          InkWell(
            onTap: _onTapRobot,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  _checkbox(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _error
                          ? 'Security check failed — tap to retry'
                          : "I'm not a robot",
                      style: TextStyle(
                          color: _error
                              ? _red
                              : _navy.withValues(alpha: 0.85),
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'security check',
            style: TextStyle(fontSize: 11, color: _navy.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  Widget _checkbox() {
    Widget child;
    if (_error) {
      child = Container(
        key: const ValueKey('error'),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _red.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _red, width: 1.5),
        ),
        child: const Icon(Icons.close_rounded, color: _red, size: 20),
      );
    } else if (_checked) {
      child = Container(
        key: const ValueKey('checked'),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.check_rounded, color: _gold, size: 20),
      );
    } else if (_checking) {
      child = const SizedBox(
        key: ValueKey('checking'),
        width: 28,
        height: 28,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
        ),
      );
    } else {
      child = Container(
        key: const ValueKey('empty'),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _navy.withValues(alpha: 0.3), width: 1.5),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}
