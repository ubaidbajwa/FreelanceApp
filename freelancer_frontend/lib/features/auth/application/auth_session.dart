import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/google_auth_config.dart';
import '../../../core/storage/saved_account_service.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../profile/data/repositories/profile_repository.dart';
import '../data/auth_repository.dart';
import '../data/models/auth_response.dart';

// Login aur signup dono ki Google + post-auth logic ek jagah — screens sirf
// apna loading state manage karti hain, asli kaam yahan (DRY).

/// Google Sign-In → backend googleLogin. AuthResponse return karta hai, ya null
/// agar user ne popup cancel kiya. Kisi asli failure pe throw karta hai.
Future<AuthResponse?> signInWithGoogle(WidgetRef ref) async {
  final googleSignIn = GoogleSignIn(
    // Web client ID — Google isi audience ka idToken banata hai, wahi backend verify karta
    serverClientId: GoogleAuthConfig.serverClientId,
    scopes: const ['email'],
  );

  final account = await googleSignIn.signIn();
  if (account == null) return null; // cancelled — koi error nahi

  final auth = await account.authentication;
  final idToken = auth.idToken;
  if (idToken == null) throw Exception('No idToken from Google');

  // Backend pe: verify + find-or-create, phir wahi AuthResponse
  return ref.read(authRepositoryProvider).googleLogin(idToken);
}

/// Post-auth ka mushtarka ritual (password login + Google dono): tokens save,
/// account yaad, phir profile-completion ke hisab se routing.
Future<void> applyAuthSuccess(
  WidgetRef ref,
  BuildContext context,
  AuthResponse response, {
  bool rememberMe = true,
}) async {
  final storage = ref.read(secureStorageProvider);
  // Purane session ke tokens pehle saaf — warna rememberMe=false pe pichla
  // refresh token bacha reh jata (galat account auto-login ho sakta tha)
  await storage.clearTokens();
  if (rememberMe) {
    await storage.saveTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
    );
  } else {
    // Access token ke baghair app ki har API call 401 hoti — session ke liye
    // zaroori; refresh token nahi to agli dafa login poochega
    await storage.saveAccessTokenOnly(response.accessToken);
  }

  // Account yaad rakho — agli dafa login screen "Welcome back" dikhayegi
  await ref.read(savedAccountServiceProvider).save(
        name: response.user.fullName,
        email: response.user.email,
      );

  // Profile check — naya user? wizard. Purana? home.
  try {
    final profile = await ref.read(profileRepositoryProvider).getMyProfile();
    if (!context.mounted) return;
    if (profile.profileCompletionPercent < 50) {
      context.go('/profile-step1');
    } else {
      context.go('/home');
    }
  } on DioException catch (_) {
    // profile check fail ho to login phir bhi kamyab hai — wizard pe bhejo
    if (context.mounted) context.go('/profile-step1');
  }
}

/// Login ke baad wali smart routing, standalone shakl mein — post-signup
/// onboarding (location/experience) khatam hone pe bhi bilkul yahi routing
/// chalti hai (applyAuthSuccess se same rules). completion < 50 → profile
/// wizard, warna /home. Profile fetch fail ho to wizard pe bhej do (user ko
/// trap mat karo).
Future<void> routeByProfileCompletion(
  WidgetRef ref,
  BuildContext context,
) async {
  try {
    final profile = await ref.read(profileRepositoryProvider).getMyProfile();
    if (!context.mounted) return;
    if (profile.profileCompletionPercent < 50) {
      context.go('/profile-step1');
    } else {
      context.go('/home');
    }
  } on DioException catch (_) {
    if (context.mounted) context.go('/profile-step1');
  }
}
