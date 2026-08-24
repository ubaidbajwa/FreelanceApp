import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth_repository.dart';
import '../../data/models/forgot_password_request.dart';

// F2.6 — Step 1: email do, backend OTP bhejega (agar email registered hai)
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();

    try {
      // 200 + generic message — email registered ho ya na ho, same jawab
      // (enumeration-safe backend), isliye seedha OTP screen pe le jao
      await ref.read(authRepositoryProvider).forgotPassword(
            ForgotPasswordRequest(email: email),
          );
      if (mounted) context.go('/reset-password', extra: email);
    } on DioException catch (e) {
      if (mounted) {
        final data = e.response?.data;
        final message = (data is Map)
            ? (data['detail'] ?? data['title'] ?? 'Something went wrong. Try again.')
            : 'Server tak pohanch nahi saka. Connection check karo.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          onPressed: () => context.go('/login'),
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
                  'FORGOT PASSWORD',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Reset your password',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Apna registered email do — hum 6-digit reset code bhejenge.',
                  style: TextStyle(
                    color: _navy.withValues(alpha: 0.55),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),

                // EMAIL — signup wala validator reuse
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputStyle('Email', Icons.mail_outline),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    final emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[\w\.]+$');
                    return emailRegex.hasMatch(v.trim()) ? null : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 32),

                // SEND RESET CODE BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _navy,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _isLoading ? null : _sendResetCode,
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
                            'Send Reset Code',
                            style: TextStyle(fontSize: 16, letterSpacing: 1),
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
