import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/error_strings.dart';
import '../../../../core/utils/platform_helper.dart';
import '../widgets/social_button.dart';
import '../../application/auth_session.dart';
import '../../application/session_controller.dart';
import '../../data/auth_repository.dart';
import '../../data/models/login_request.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  bool _prefilled = false; // sirf pehli dafa extra se email bharni hai

  // GoRouterState.of(context) initState mein nahi chalta — yahan safe hai
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final extra = GoRouterState.of(context).extra;
    if (extra is String) _emailController.text = extra; // safe cast, 'as String' crash se bachao
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await ref.read(authRepositoryProvider).login(
            LoginRequest(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            ),
          );
      if (!mounted) return;
      await applyAuthSuccess(ref, context, response, rememberMe: _rememberMe);
    } on DioException catch (e) {
      final message = _errorMessage(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Google Sign-In — shared helper (popup + backend), phir wahi post-auth ritual.
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final response = await signInWithGoogle(ref);
      if (response == null) return; // user ne popup cancel kiya — koi error nahi
      if (!mounted) return;
      await applyAuthSuccess(ref, context, response); // default: session yaad rakho
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Google sign-in failed. Try again.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      return data['detail'] ?? data['title'] ?? 'Something went wrong. Try again.';
    }
    return 'Something went wrong. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    // Session interceptor ne expire pe yahan redirect kiya — ek dafa
    // session-expired snackbar dikhao, phir acknowledge (dobara na dikhe).
    // watch se rebuild hota hai jab status expired banta hai (mount pe already
    // expired ho ya baad mein).
    if (ref.watch(sessionControllerProvider) == SessionStatus.expired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(ErrorStrings.sessionExpired),
            backgroundColor: Colors.red.shade700,
          ),
        );
        ref.read(sessionControllerProvider.notifier).acknowledge();
      });
    }

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                const Text(
                  'Sign in',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                // "New here? Join now" — Welcome Back wale pattern jaisa gold link
                Row(
                  children: [
                    Text('New here? ',
                        style: TextStyle(color: _navy.withValues(alpha: 0.7))),
                    GestureDetector(
                      onTap: () => context.go('/signup'),
                      child: const Text('Join now',
                          style: TextStyle(
                              color: _gold, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Sign in social buttons — Apple har platform pe; Web: +Microsoft
                ...socialProvidersForSignIn().map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: SocialButton(
                          provider: p,
                          // Google = real handler; loading pe disable. Baaki "Coming soon".
                          onGoogleTap: _isLoading ? null : _handleGoogleSignIn,
                        ),
                      ),
                    )),
                const SizedBox(height: 4),
                Text(
                  'By continuing, you agree to our Terms of Service and Privacy Policy.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12, color: _navy.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Divider(color: _navy.withValues(alpha: 0.2))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or',
                        style: TextStyle(color: _navy.withValues(alpha: 0.5))),
                  ),
                  Expanded(child: Divider(color: _navy.withValues(alpha: 0.2))),
                ]),
                const SizedBox(height: 24),

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
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _inputStyle('Password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Password is required' : null,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      activeColor: _navy,
                      onChanged: (value) =>
                          setState(() => _rememberMe = value ?? false),
                    ),
                    const Text('Remember me', style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.go('/forgot-password'),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(color: _navy),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white, // navy pill, white text
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _isLoading ? null : _handleLogin,
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
                            'Sign In',
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
