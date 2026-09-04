import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../profile/data/repositories/profile_repository.dart';

// Shell ke liye profile ka summary: name, headline, photo, completion%, role.
// JWT ke primary_role claim se role milta hai (0=freelancer, 1=client).

class ProfileSummaryState {
  final bool loading;
  final String? error;
  final String displayName;
  final String? headline;
  final String? photoUrl;
  final int completionPercent;
  final int role; // 0 = freelancer, 1 = client

  const ProfileSummaryState({
    this.loading = false,
    this.error,
    this.displayName = '',
    this.headline,
    this.photoUrl,
    this.completionPercent = 0,
    this.role = 0,
  });

  ProfileSummaryState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    String? displayName,
    String? headline,
    String? photoUrl,
    int? completionPercent,
    int? role,
  }) => ProfileSummaryState(
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    displayName: displayName ?? this.displayName,
    headline: headline ?? this.headline,
    photoUrl: photoUrl ?? this.photoUrl,
    completionPercent: completionPercent ?? this.completionPercent,
    role: role ?? this.role,
  );
}

class _ProfileJwtClaims {
  final int role;
  final String? fullName;

  const _ProfileJwtClaims({required this.role, this.fullName});
}

class ProfileSummaryNotifier extends Notifier<ProfileSummaryState> {
  @override
  ProfileSummaryState build() {
    Future.microtask(load);
    return const ProfileSummaryState(loading: true);
  }

  Future<void> load() async {
    final claims = await _claimsFromJwt();
    final jwtName = claims.fullName;
    final fallbackName = (jwtName != null && jwtName.isNotEmpty)
        ? jwtName
        : state.displayName;
    state = state.copyWith(
      loading: true,
      clearError: true,
      displayName: fallbackName,
      role: claims.role,
    );
    try {
      final profile = await ref.read(profileRepositoryProvider).getMyProfile();
      final profileName = profile.displayName;
      state = ProfileSummaryState(
        displayName: (profileName != null && profileName.isNotEmpty)
            ? profileName
            : fallbackName,
        headline: profile.headline,
        photoUrl: profile.profilePhotoUrl,
        completionPercent: profile.profileCompletionPercent,
        role: claims.role,
      );
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not load profile');
    }
  }

  // JWT payload mein primary_role ("0"/"1") aur full_name fallback hota hai.
  Future<_ProfileJwtClaims> _claimsFromJwt() async {
    try {
      final token = await ref.read(secureStorageProvider).getAccessToken();
      if (token == null) return const _ProfileJwtClaims(role: 0);
      final parts = token.split('.');
      if (parts.length != 3) return const _ProfileJwtClaims(role: 0);
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final data = jsonDecode(payload) as Map<String, dynamic>;
      return _ProfileJwtClaims(
        role: int.tryParse((data['primary_role'] as String?) ?? '0') ?? 0,
        fullName: data['full_name'] as String?,
      );
    } catch (_) {
      return const _ProfileJwtClaims(role: 0);
    }
  }
}

final profileSummaryProvider =
    NotifierProvider<ProfileSummaryNotifier, ProfileSummaryState>(
      ProfileSummaryNotifier.new,
    );
