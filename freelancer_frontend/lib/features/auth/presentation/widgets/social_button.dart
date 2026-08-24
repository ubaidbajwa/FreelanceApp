import 'package:flutter/material.dart';
import '../../../../core/utils/platform_helper.dart';

class SocialButton extends StatelessWidget {
  final SocialProvider provider;
  final bool joinStyle; // Join screen: sab "Continue with ..."
  // Google ke liye real handler — screen deta hai. null ho to (ya baaki
  // providers) abhi bhi "Coming soon" hi dikhega.
  final VoidCallback? onGoogleTap;
  const SocialButton({
    super.key,
    required this.provider,
    this.joinStyle = false,
    this.onGoogleTap,
  });

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1633);
    final (name, letter) = switch (provider) {
      SocialProvider.google => ('Google', 'G'),
      SocialProvider.apple => ('Apple', ''),
      SocialProvider.microsoft => ('Microsoft', 'M'),
    };
    // Sign in screen: Google "Continue with", baaki "Sign in with" (purana behavior).
    // Join screen (joinStyle=true): sab "Continue with ...".
    final verb = (joinStyle || provider == SocialProvider.google)
        ? 'Continue with'
        : 'Sign in with';
    final label = '$verb $name';
    // Google + handler mila to real sign-in; warna purana "Coming soon".
    final onPressed = (provider == SocialProvider.google && onGoogleTap != null)
        ? onGoogleTap
        : () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Coming soon!')), // baaki F7 mein
            );
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(), // tumhara pill style
        side: BorderSide(color: navy.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        foregroundColor: navy,
      ),
      icon: provider == SocialProvider.apple
          ? const Icon(Icons.apple, size: 22, color: navy)
          : Text(letter,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: navy)),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}