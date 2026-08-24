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
  }) =>
      ProfileSummaryState(
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        displayName: displayName ?? this.displayName,
        headline: headline ?? this.headline,
        photoUrl: photoUrl ?? this.photoUrl,
        completionPercent: completionPercent ?? this.completionPercent,
        role: role ?? this.role,
      );
}

class ProfileSummaryNotifier extends Notifier<ProfileSummaryState> {
  @override
  ProfileSummaryState build() {
    Future.microtask(load);
    return const ProfileSummaryState(loading: true);
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final role = await _roleFromJwt();
      final profile = await ref.read(profileRepositoryProvider).getMyProfile();
      state = ProfileSummaryState(
        displayName: profile.displayName ?? '',
        headline: profile.headline,
        photoUrl: profile.profilePhotoUrl,
        completionPercent: profile.profileCompletionPercent,
        role: role,
      );
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not load profile');
    }
  }

  // JWT payload mein primary_role claim hota hai ("0" ya "1" as string)
  Future<int> _roleFromJwt() async {
    try {
      final token = await ref.read(secureStorageProvider).getAccessToken();
      if (token == null) return 0;
      final parts = token.split('.');
      if (parts.length != 3) return 0;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final data = jsonDecode(payload) as Map<String, dynamic>;
      return int.tryParse((data['primary_role'] as String?) ?? '0') ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

final profileSummaryProvider =
    NotifierProvider<ProfileSummaryNotifier, ProfileSummaryState>(
  ProfileSummaryNotifier.new,
);
