import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/user_role.dart';
import '../../../../core/presentation/widgets/app_logo.dart';
import '../../../../core/utils/platform_helper.dart';
import '../../../auth/application/auth_session.dart';
import '../../../auth/application/signup_flow_notifier.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/widgets/social_button.dart';
import '../../providers/onboarding_providers.dart';

// LinkedIn-style progressive "Join" flow — ek hi screen, 3 steps (_step 0..2).
// Step 0: email → Step 1: +password → Step 2: naam + role → register (existing logic).
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  final _formKey = GlobalKey<FormState>(); // form ka remote control
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  int _step = 0; // 0 = email, 1 = +password, 2 = naam + role
  bool _obscurePassword = true;
  bool _checkingEmail = false; // check-email API chal rahi hai
  bool _googleLoading = false; // Google sign-in chal raha hai
  String? _emailExistsError; // backend se aaya duplicate error — field pe dikhta hai

  @override
  void dispose() {
    // Controllers ki safai — memory leak se bachao (aapko ye pata hai! 😄)
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Progress: step0 → 30%, step1 → 60%, step2 → 90%
  double get _progress => const [0.30, 0.60, 0.90][_step];

  // Password strength: 0 = weak, 1 = medium, 2 = strong (existing logic)
  int get _passwordStrength {
    final p = _passwordController.text;
    if (p.length < 8) return 0;
    final hasUpper = p.contains(RegExp(r'[A-Z]'));
    final hasDigit = p.contains(RegExp(r'[0-9]'));
    final hasSpecial = p.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    if (hasUpper && hasDigit && hasSpecial) return 2;
    if (hasUpper && hasDigit) return 1;
    return 0;
  }

  // --- Validators (existing rules reuse) ---
  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[\w\.]+$');
    if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
    return _emailExistsError; // backend duplicate check ka result (null = theek)
  }

  String? _validatePassword(String? v) {
    if (v == null || v.length < 8) return 'Minimum 8 characters';
    if (_passwordStrength == 0) return 'Add uppercase, number & symbol';
    return null;
  }

  // Primary button — har step pe alag kaam
  Future<void> _onPrimaryPressed() async {
    // validate() sirf un fields ko check karta hai jo abhi tree mein hain
    if (!_formKey.currentState!.validate()) return;
    if (_step == 0) {
      // "Agree & Join" — pehle backend se poocho: email pehle se to nahi?
      final ok = await _checkEmailAvailable();
      if (ok && mounted) setState(() => _step = 1);
    } else if (_step == 1) {
      setState(() => _step = 2);
    } else {
      _saveAndContinue();
    }
  }

  // true = email available (aage badho), false = pehle se exist karti hai
  Future<bool> _checkEmailAvailable() async {
    setState(() {
      _checkingEmail = true;
      _emailExistsError = null;
    });
    try {
      final exists = await ref
          .read(authRepositoryProvider)
          .emailExists(_emailController.text.trim());
      if (!mounted) return false;
      if (exists) {
        setState(() => _emailExistsError =
            'This email is already registered. Sign in instead.');
        _formKey.currentState!.validate(); // error field ke neeche dikhao
        return false;
      }
      return true;
    } on DioException {
      // Network/server issue pe user ko roko mat — register pe backend
      // waise bhi duplicate pe 409 dega (backstop)
      return true;
    } finally {
      if (mounted) setState(() => _checkingEmail = false);
    }
  }

  // Final step: register ABHI nahi hoti — data flow-notifier mein save karke
  // security-check screen pe bhejte hain (register wahan, phir OTP → auto-login).
  void _saveAndContinue() {
    final role = ref.read(selectedRoleProvider);
    if (role == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please choose how you want to use Skillora')),
      );
      return;
    }

    ref.read(signupFlowProvider.notifier).setBasics(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          role: role.value,
        );

    context.go('/security-check');
  }

  // "Continue with Google" — shared helper. Naya user ho ya returning, backend
  // find-or-create karta hai; email verify Google se already hoti hai to seedha
  // routing (koi OTP/security-check nahi).
  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleLoading = true);
    try {
      final response = await signInWithGoogle(ref);
      if (response == null) return; // popup cancel — koi error nahi
      if (!mounted) return;
      await applyAuthSuccess(ref, context, response);
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
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedRole = ref.watch(selectedRoleProvider);

    return PopScope(
      // Step > 0 pe back sirf ek step peeche jaye, screen se bahar nahi
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _step > 0) setState(() => _step--);
      },
      child: Scaffold(
        backgroundColor: _ivory,
        body: SafeArea(
          child: SingleChildScrollView( // keyboard khule to scroll ho sake
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Brand row — LinkedIn-logo style (logo + wordmark side by side)
                  Row(
                    children: const [
                      AppLogo(size: 32, showWordmark: false),
                      SizedBox(width: 10),
                      Text(
                        'SKILLORA',
                        style: TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Slim progress bar (gold fill, navy 10% track, rounded)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 6,
                      color: _gold,
                      backgroundColor: _navy.withValues(alpha: 0.10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Create account',
                          style: TextStyle(
                              fontSize: 13,
                              color: _navy.withValues(alpha: 0.6))),
                      const Spacer(),
                      Text('${(_progress * 100).round()}%',
                          style: TextStyle(
                              fontSize: 13,
                              color: _navy.withValues(alpha: 0.6))),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Heading — hamesha visible
                  const Text('Join Skillora',
                      style: TextStyle(
                          color: _navy,
                          fontSize: 30,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('or ',
                          style: TextStyle(color: _navy.withValues(alpha: 0.7))),
                      GestureDetector(
                        onTap: () => context.go('/login'),
                        child: const Text('Sign in',
                            style: TextStyle(
                                color: _gold, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Animated field area — creds (step 0/1) ↔ profile (step 2)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _step < 2
                        ? _credentialsGroup()
                        : _profileGroup(selectedRole),
                  ),
                  const SizedBox(height: 24),

                  // Legal text — sirf step 0 aur 1 pe (button ke upar)
                  if (_step < 2) ...[
                    Text(
                      "By clicking Agree & Join, you agree to Skillora's "
                      'Terms of Service and Privacy Policy.',
                      style: TextStyle(
                          fontSize: 12, color: _navy.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Primary button — navy pill, white text
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _checkingEmail ? null : _onPrimaryPressed,
                      child: _checkingEmail
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_step == 2 ? 'Continue' : 'Agree & Join',
                              style: const TextStyle(
                                  fontSize: 16, letterSpacing: 1)),
                    ),
                  ),

                  // Social section — SIRF step 0 pe, button ke neeche (LinkedIn style)
                  if (_step == 0) ...[
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                          child: Divider(color: _navy.withValues(alpha: 0.2))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or',
                            style:
                                TextStyle(color: _navy.withValues(alpha: 0.5))),
                      ),
                      Expanded(
                          child: Divider(color: _navy.withValues(alpha: 0.2))),
                    ]),
                    const SizedBox(height: 16),
                    ...socialProvidersForJoin().map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: SocialButton(
                            provider: p,
                            joinStyle: true,
                            // Google = real handler; baaki abhi "Coming soon"
                            onGoogleTap:
                                _googleLoading ? null : _handleGoogleSignIn,
                          ),
                          ),
                        )),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Step 0/1 — email (hamesha) + password (step 1 pe AnimatedSize se slide-in)
  Widget _credentialsGroup() {
    return Column(
      key: const ValueKey('creds'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _inputStyle('Email', Icons.mail_outline),
          validator: _validateEmail,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _step >= 1
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      onChanged: (_) => setState(() {}), // strength bar update
                      decoration:
                          _inputStyle('Password', Icons.lock_outline).copyWith(
                        helperText:
                            'Min 8 chars with an uppercase letter, number & symbol.',
                        helperMaxLines: 2,
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 8),
                    _strengthBar(),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  // Password strength bar (existing logic)
  Widget _strengthBar() {
    return Row(children: [
      for (int i = 0; i < 3; i++)
        Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i <= _passwordStrength &&
                      _passwordController.text.isNotEmpty
                  ? [Colors.red, Colors.orange, Colors.green][_passwordStrength]
                  : Colors.grey.shade300,
            ),
          ),
        ),
    ]);
  }

  // Step 2 — first/last name + role cards
  Widget _profileGroup(UserRole? selectedRole) {
    return Column(
      key: const ValueKey('profile'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _firstNameController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputStyle('First name', Icons.person_outline),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'First name is required' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _lastNameController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputStyle('Last name', Icons.person_outline),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Last name is required' : null,
        ),
        const SizedBox(height: 20),
        _roleCard(
          role: UserRole.freelancer, // 0
          title: 'I want to work',
          subtitle: 'Find projects & get hired',
          icon: Icons.work_outline_rounded,
          selected: selectedRole == UserRole.freelancer,
        ),
        const SizedBox(height: 12),
        _roleCard(
          role: UserRole.client, // 1
          title: 'I want to hire',
          subtitle: 'Post jobs & find talent',
          icon: Icons.business_center_outlined,
          selected: selectedRole == UserRole.client,
        ),
      ],
    );
  }

  Widget _roleCard({
    required UserRole role,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
  }) {
    return InkWell(
      onTap: () => ref.read(selectedRoleProvider.notifier).select(role),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? _navy : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _gold : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 30, color: selected ? _gold : _navy),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : _navy)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: selected
                              ? Colors.white70
                              : Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: _gold),
          ],
        ),
      ),
    );
  }

  // Input fields ka common style — DRY principle!
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
