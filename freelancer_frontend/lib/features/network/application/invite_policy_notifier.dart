import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../profile/data/models/profile_model.dart';
import '../../profile/data/repositories/profile_repository.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class InvitePolicyState {
  final ConnectionInvitePolicy policy;
  final bool loading; // initial GET in progress
  final bool saving;  // optimistic PUT in progress — disables concurrent taps
  final String? error;

  const InvitePolicyState({
    this.policy = ConnectionInvitePolicy.everyone,
    this.loading = false,
    this.saving = false,
    this.error,
  });

  InvitePolicyState copyWith({
    ConnectionInvitePolicy? policy,
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
  }) =>
      InvitePolicyState(
        policy: policy ?? this.policy,
        loading: loading ?? this.loading,
        saving: saving ?? this.saving,
        error: clearError ? null : (error ?? this.error),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class InvitePolicyNotifier extends Notifier<InvitePolicyState> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  InvitePolicyState build() {
    Future.microtask(_load);
    return const InvitePolicyState(loading: true);
  }

  Future<void> _load() async {
    state = InvitePolicyState(loading: true);
    try {
      final profile = await _repo.getMyProfile();
      state = InvitePolicyState(policy: profile.invitePolicy);
    } catch (e) {
      // Shared mapper — offline / session-expired / server alag alag padhein.
      state = InvitePolicyState(error: appErrorMessage(e));
    }
  }

  Future<void> retry() => _load();

  // OPTIMISTIC: flip policy immediately, PUT to backend.
  // On failure: revert + return error message for the screen to show as SnackBar.
  // Concurrent saves are rejected (saving guard) — user must wait for the
  // in-flight request to settle before selecting a different option.
  Future<String?> setPolicy(ConnectionInvitePolicy newPolicy) async {
    if (state.saving || state.policy == newPolicy) return null;
    final prev = state.policy;
    state = state.copyWith(policy: newPolicy, saving: true);
    try {
      await _repo.updateProfile(
        UpdateProfileRequest(invitePolicy: newPolicy.index),
      );
      state = state.copyWith(saving: false);
      return null;
    } catch (e) {
      state = state.copyWith(policy: prev, saving: false);
      return appErrorMessage(e);
    }
  }
}

final invitePolicyProvider =
    NotifierProvider<InvitePolicyNotifier, InvitePolicyState>(
        InvitePolicyNotifier.new);
