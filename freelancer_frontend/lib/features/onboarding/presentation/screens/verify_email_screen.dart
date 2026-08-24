import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../../../core/storage/saved_account_service.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../../auth/application/signup_flow_notifier.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/data/models/login_request.dart';
import '../../../auth/data/models/verify_email_request.dart';
import '../../../auth/data/models/resend_otp_request.dart';

// F2.4 — OTP verify screen: register ke baad email pe aya 6-digit code yahan dalta hai
class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  // 6 controllers + 6 focus nodes — har digit box ka apna set
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;

  Timer? _timer; // ? = nullable, kyunki shuru mein timer hai hi nahi
  int _cooldown = 0; // 0 = button enabled, >0 = itne seconds baaki

  @override
  void dispose() {
    _timer?.cancel(); // ?. = agar timer null nahi hai to cancel
    // Dono lists ke har item ko dispose karo — warna memory leak
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      // Digit type hua → agla box focus
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      // Backspace → pichla box focus
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {}); // Verify button enable/disable refresh
  }

  // 6 boxes ka text jod kar ek string — "483920"
  String get _otp => _controllers.map((c) => c.text).join();

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  // Backend ProblemDetails (RFC 7807) se message nikaalo — 'detail' field mein hota hai
  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      return data['detail'] ?? data['title'] ?? 'Something went wrong. Try again.';
    }
    return 'Server tak pohanch nahi saka. Connection check karo.';
  }

  Future<void> _verify() async {
    if (_otp.length != 6) {
      _showSnack('Please enter the complete 6-digit code', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Success = 204 No Content — koi body parse nahi karni
      await ref.read(authRepositoryProvider).verifyEmail(
            VerifyEmailRequest(email: widget.email, otp: _otp),
          );
      if (!mounted) return;

      // Signup flow se aaye (password mojood) to auto-login karo. Forgot-password
      // OTP flow mein password nahi hota — wo path bilkul untouched rehta hai.
      final flow = ref.read(signupFlowProvider);
      if (flow.hasPassword && flow.email == widget.email) {
        await _autoLoginAndContinue(flow.password);
      } else {
        _showSnack('Email verified! Please sign in.');
        context.go('/login');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      _showSnack(_errorMessage(e), isError: true); // "Invalid or expired OTP" waghera
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Verify ke foran baad seedha login — user ko dobara password nahi dalna padta
  Future<void> _autoLoginAndContinue(String password) async {
    try {
      final response = await ref.read(authRepositoryProvider).login(
            LoginRequest(email: widget.email, password: password),
          );

      final storage = ref.read(secureStorageProvider);
      await storage.clearTokens();
      await storage.saveTokens(
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      );

      // Account yaad rakho — welcome-back flow ke liye (existing save)
      await ref.read(savedAccountServiceProvider).save(
            name: response.user.fullName,
            email: widget.email,
          );

      if (!mounted) return;
      context.go('/onboarding-location');
    } on DioException {
      // Edge case: email verify ho gaya par auto-login fail — purana behavior
      if (!mounted) return;
      _showSnack('Account verified! Please sign in.');
      context.go('/login');
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).resendOtp(
            ResendOtpRequest(email: widget.email),
          );
      if (!mounted) return;
      _showSnack('OTP dobara bhej diya gaya');
      _startCooldown();
    } on DioException catch (e) {
      if (!mounted) return;
      _showSnack(_errorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startCooldown() {
    setState(() => _cooldown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown > 1) {
        setState(() => _cooldown--);
      } else {
        setState(() => _cooldown = 0);
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Text(
                'VERIFY EMAIL',
                style: TextStyle(
                  color: _gold,
                  fontSize: 12,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your inbox',
                style: TextStyle(
                  color: _navy,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // Email text mein dikhti hai — user ko pata ho code kahan gaya
              Text(
                'We sent a 6-digit code to\n${widget.email}',
                style: TextStyle(
                  color: _navy.withValues(alpha: 0.55),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 40),

              // 6 OTP BOXES
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 48,
                    height: 56,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      onChanged: (value) => _onDigitChanged(index, value),
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: _navy,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        counterText: '', // maxLength ka "0/1" chhupao
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _gold.withValues(alpha: 0.45),
                            width: 1.2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _gold, width: 1.5),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 40),

              // VERIFY BUTTON
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: _isLoading ? null : _verify,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(fontSize: 16, letterSpacing: 1),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: _cooldown == 0 ? _resendOtp : null,
                child: Text(
                  _cooldown == 0 ? 'Resend Code' : 'Resend in ${_cooldown}s',
                  style: const TextStyle(color: _navy),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
