import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth_repository.dart';
import '../../data/models/forgot_password_request.dart';
import '../../data/models/reset_password_request.dart';

// F2.6 — Step 2: OTP + naya password → reset (verify_email_screen ka copy-adapt)
class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  // 6 controllers + 6 focus nodes — verify_email wala pattern
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());

  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  Timer? _timer;
  int _cooldown = 0; // 0 = resend enabled, >0 = itne seconds baaki

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  String get _otp => _otpControllers.map((c) => c.text).join();

  // Password strength: 0 = weak, 1 = medium, 2 = strong (signup se reuse)
  int get _passwordStrength {
    final p = _passwordController.text;
    if (p.length < 8) return 0;
    final hasUpper = p.contains(RegExp(r'[A-Z]'));
    final hasDigit = p.contains(RegExp(r'[0-9]'));
    final hasSpecial = p.contains(RegExp(r'[^a-zA-Z0-9]'));
    if (hasUpper && hasDigit && hasSpecial) return 2;
    if (hasUpper && hasDigit) return 1;
    return 0;
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  // ProblemDetails ke sath FluentValidation ka 'errors' map bhi handle karo —
  // 400 validation error mein message 'detail' mein NAHI, errors map mein hota hai
  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      if (data['detail'] != null) return data['detail'];
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      return data['title'] ?? 'Something went wrong. Try again.';
    }
    return 'Server tak pohanch nahi saka. Connection check karo.';
  }

  Future<void> _resetPassword() async {
    if (_otp.length != 6) {
      _showSnack('Please enter the complete 6-digit code', isError: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(
            ResetPasswordRequest(
              email: widget.email,
              otp: _otp,
              newPassword: _passwordController.text,
              // ConfirmPassword backend pe nahi jata — sirf local check tha
            ),
          );
      if (!mounted) return;
      _showSnack('Password reset ho gaya! Naye password se sign in karo.');
      context.go('/login');
    } on DioException catch (e) {
      if (!mounted) return;
      _showSnack(_errorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);
    try {
      // Resend = forgotPassword dobara call — wahi OTP flow
      await ref.read(authRepositoryProvider).forgotPassword(
            ForgotPasswordRequest(email: widget.email),
          );
      if (!mounted) return;
      _showSnack('Naya reset code bhej diya gaya');
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
      appBar: AppBar(
        backgroundColor: _ivory,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _navy),
          onPressed: () => context.go('/forgot-password'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Text(
                  'RESET PASSWORD',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create new password',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We sent a 6-digit code to\n${widget.email}',
                  style: TextStyle(
                    color: _navy.withValues(alpha: 0.55),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),

                // 6 OTP BOXES — verify_email wala copy
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 48,
                      height: 56,
                      child: TextField(
                        controller: _otpControllers[index],
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
                          counterText: '',
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
                            borderSide:
                                const BorderSide(color: _gold, width: 1.5),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),

                // NEW PASSWORD
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onChanged: (_) => setState(() {}), // strength bar update
                  decoration:
                      _inputStyle('New Password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  // Sirf min-length local — baaki rules backend FluentValidation
                  // se aayenge (special char wala error SnackBar mein dikhega)
                  validator: (v) =>
                      (v == null || v.length < 8) ? 'Minimum 8 characters' : null,
                ),
                const SizedBox(height: 8),

                // STRENGTH BAR — signup se reuse
                Row(children: [
                  for (int i = 0; i < 3; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: i <= _passwordStrength &&
                                  _passwordController.text.isNotEmpty
                              ? [
                                  Colors.red,
                                  Colors.orange,
                                  Colors.green
                                ][_passwordStrength]
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 16),

                // CONFIRM PASSWORD — sirf local check, backend pe nahi jata
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscureConfirm,
                  decoration:
                      _inputStyle('Confirm Password', Icons.lock_outline)
                          .copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) => (v != _passwordController.text)
                      ? 'Passwords match nahi karte'
                      : null,
                ),
                const SizedBox(height: 32),

                // RESET BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _navy,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _isLoading ? null : _resetPassword,
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
                            'Reset Password',
                            style: TextStyle(fontSize: 16, letterSpacing: 1),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // RESEND — wahi 60s cooldown pattern
                Center(
                  child: _cooldown > 0
                      ? Text(
                          'Resend code in ${_cooldown}s',
                          style:
                              TextStyle(color: _navy.withValues(alpha: 0.55)),
                        )
                      : TextButton(
                          onPressed: _isLoading ? null : _resendCode,
                          child: const Text(
                            "Didn't get the code? Resend",
                            style: TextStyle(color: _navy),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _navy),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 1.5),
        ),
      );
}
