// My Connections notifier — ek baar API se load, phir client-side filter.
// People screen mein debounced server-search hai kyunki list large + paginated
// hai; yahan sari connections ek baar aati hain (generally small set) to
// client-side filter sahi hai — har keystroke pe API call ki zaroorat nahi.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';

import '../data/connections_repository.dart';
import '../data/models/connection_models.dart';

class MyConnectionsState {
  final bool loading;
  final String? error;
  final List<ConnectionUser> connections; // API se mila poora list
  final String filter; // search field ka current text
  final List<ConnectionUser> filtered; // connections filtered by filter

  const MyConnectionsState({
    this.loading = false,
    this.error,
    this.connections = const [],
    this.filter = '',
    this.filtered = const [],
  });

  MyConnectionsState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<ConnectionUser>? connections,
    String? filter,
    List<ConnectionUser>? filtered,
  }) =>
      MyConnectionsState(
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        connections: connections ?? this.connections,
        filter: filter ?? this.filter,
        filtered: filtered ?? this.filtered,
      );
}

// Riverpod 3 Notifier (StateProvider legacy — use nahi karna).
class MyConnectionsNotifier extends Notifier<MyConnectionsState> {
  ConnectionsRepository get _repo => ref.read(connectionsRepositoryProvider);

  @override
  MyConnectionsState build() {
    Future.microtask(load); // PeopleNotifier wala pattern
    return const MyConnectionsState(loading: true);
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final list = await _repo.getMyConnections();
      state = state.copyWith(
        loading: false,
        connections: list,
        filtered: _applyFilter(list, state.filter),
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: _messageOf(e));
    }
  }

  Future<void> refresh() => load();

  // Har keystroke pe in-memory filter — API call nahi hoti.
  void onFilterChanged(String value) {
    state = state.copyWith(
      filter: value,
      filtered: _applyFilter(state.connections, value),
    );
  }

  List<ConnectionUser> _applyFilter(List<ConnectionUser> list, String filter) {
    if (filter.trim().isEmpty) return list;
    final q = filter.trim().toLowerCase();
    return list
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.headline?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  // Shared mapper — offline / session-expired / server / 4xx-detail alag messages.
  String _messageOf(Object e) => appErrorMessage(e);
}

final myConnectionsProvider =
    NotifierProvider<MyConnectionsNotifier, MyConnectionsState>(
        MyConnectionsNotifier.new);
