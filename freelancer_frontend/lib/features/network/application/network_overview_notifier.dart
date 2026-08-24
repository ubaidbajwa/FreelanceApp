import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../data/models/network_models.dart';
import '../data/network_repository.dart';

class NetworkOverviewState {
  final bool loading;
  final String? error;
  final NetworkOverview? overview;

  const NetworkOverviewState({
    this.loading = true,
    this.error,
    this.overview,
  });

  NetworkOverviewState copyWith({
    bool? loading,
    String? error,
    NetworkOverview? overview,
    bool clearError = false,
  }) =>
      NetworkOverviewState(
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        overview: overview ?? this.overview,
      );
}

class NetworkOverviewNotifier extends Notifier<NetworkOverviewState> {
  NetworkRepository get _repo => ref.read(networkRepositoryProvider);

  @override
  NetworkOverviewState build() {
    Future.microtask(load);
    return const NetworkOverviewState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final overview = await _repo.getOverview();
      state = state.copyWith(loading: false, overview: overview);
    } catch (e) {
      state = state.copyWith(loading: false, error: _messageOf(e));
    }
  }

  Future<void> refresh() => load();

  // Shared mapper — offline / session-expired / server error / 4xx-detail alag
  // alag messages (pehle sab ek generic line ban jate the).
  String _messageOf(Object e) => appErrorMessage(e);
}

final networkOverviewProvider =
    NotifierProvider<NetworkOverviewNotifier, NetworkOverviewState>(
  NetworkOverviewNotifier.new,
);
