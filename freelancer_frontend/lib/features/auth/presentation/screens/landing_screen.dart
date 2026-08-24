import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/error_mapper.dart';
import '../../../../core/presentation/widgets/app_logo.dart';
import '../../application/auth_session.dart';
import '../../auth_strings.dart';

// Landing screen — fresh-install / logged-out entry point.
// Splash navigates here when no session is found; authenticated users bypass
// this entirely (splash goes to /home or /profile-step1 directly).
//
// Actions:
//   Continue with Google → Google Sign-In flow (wires to existing signInWithGoogle)
//   Sign in with Email   → /login
//   Join now             → /signup
//
// Google Sign-In note: Flutter-side code is complete. Android configuration is
// INCOMPLETE — google-services.json is missing and the google-services Gradle
// plugin is not applied. The button is present; it will fail on Android until
// those two items are added. See the build report for details.
class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final response = await signInWithGoogle(ref);
      if (response == null) return; // user cancelled popup — not an error
      if (!mounted) return;
      await applyAuthSuccess(ref, context, response);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appErrorMessage(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      // Every exit path clears the spinner — no stuck loading state is possible.
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Upper area: logo + tagline sit in the upper-middle third.
              const Spacer(flex: 3),
              _buildBrandHero(),
              // Large vertical gap — action buttons land in the lower third.
              const Spacer(flex: 4),
              // Action buttons
              _buildGoogleButton(),
              const SizedBox(height: 12),
              _buildEmailButton(),
              const SizedBox(height: 24),
              _buildOrDivider(),
              const SizedBox(height: 20),
              _buildJoinRow(),
              const SizedBox(height: 28),
              _buildLegalLine(),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHero() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(80 * 0.28),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const AppLogo(size: 80, showWordmark: false),
        ),
        const SizedBox(height: 20),
        const Text(
          'SKILLORA',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _navy,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          AuthStrings.landingTagline,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: _navy.withValues(alpha: 0.58),
            height: 1.45,
          ),
        ),
      ],
    );
  }

  // Primary button: navy fill, white text, StadiumBorder.
  // Matches the primary button pattern from login_screen.dart / signup_screen.dart
  // (FilledButton, backgroundColor: _navy, foregroundColor: Colors.white, StadiumBorder).
  // Google G as icon; switches to a white spinner while the flow is in flight.
  // Both buttons are disabled during loading so a double-tap cannot start two flows.
  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          // Padding-based sizing — no fixed height so long translated labels wrap.
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 20,
            vertical: 15,
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        onPressed: _isLoading ? null : _handleGoogleSignIn,
        icon: _isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'G',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
        label: const Text(AuthStrings.continueWithGoogle),
      ),
    );
  }

  Widget _buildEmailButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _navy,
          shape: const StadiumBorder(),
          side: BorderSide(color: _navy.withValues(alpha: 0.35), width: 1.2),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 20,
            vertical: 15,
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        onPressed: _isLoading ? null : () => context.go('/login'),
        icon: const Icon(Icons.mail_outline, size: 20),
        label: const Text(AuthStrings.signInWithEmail),
      ),
    );
  }

  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: _navy.withValues(alpha: 0.2))),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
          child: Text(
            AuthStrings.orDivider,
            style: TextStyle(
              color: _navy.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(child: Divider(color: _navy.withValues(alpha: 0.2))),
      ],
    );
  }

  // Wrap instead of Row — a long translated string for "New to Skillora?" can
  // break to the next line rather than clipping or overflowing a fixed Row.
  Widget _buildJoinRow() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          AuthStrings.newToSkillora,
          style: TextStyle(
            color: _navy.withValues(alpha: 0.7),
            fontSize: 15,
          ),
        ),
        GestureDetector(
          onTap: _isLoading ? null : () => context.go('/signup'),
          child: const Text(
            AuthStrings.joinNow,
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  // Terms and Privacy are visually tappable (gold) but inert: no routes or
  // URLs exist yet. Present as required by spec. Wire onTap when routes are added.
  Widget _buildLegalLine() {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: AuthStrings.legalPrefix),
          TextSpan(
            text: AuthStrings.legalTerms,
            style: const TextStyle(color: _gold),
          ),
          const TextSpan(text: AuthStrings.legalAnd),
          TextSpan(
            text: AuthStrings.legalPrivacy,
            style: const TextStyle(color: _gold),
          ),
          const TextSpan(text: AuthStrings.legalSuffix),
        ],
      ),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        color: _navy.withValues(alpha: 0.5),
        height: 1.5,
      ),
    );
  }
}
