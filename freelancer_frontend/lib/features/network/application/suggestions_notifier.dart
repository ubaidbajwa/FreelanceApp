import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../connections/data/connections_repository.dart';
import '../data/models/network_models.dart';
import '../data/network_repository.dart';
import 'network_overview_notifier.dart';

class SuggestionsState {
  final List<Suggestion> items;
  final int page;
  final bool hasNextPage;
  final bool loading;
  final bool loadingMore;
  final String? error;
  // Per-card in-flight guard — covers both connect and dismiss actions
  final Set<String> busyIds;
  // Session-persistent "sent" set — card stays in list showing "Pending" label
  final Set<String> requestedIds;

  const SuggestionsState({
    this.items = const [],
    this.page = 0,
    this.hasNextPage = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.busyIds = const {},
    this.requestedIds = const {},
  });

  SuggestionsState copyWith({
    List<Suggestion>? items,
    int? page,
    bool? hasNextPage,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool clearError = false,
    Set<String>? busyIds,
    Set<String>? requestedIds,
  }) =>
      SuggestionsState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasNextPage: hasNextPage ?? this.hasNextPage,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
        busyIds: busyIds ?? this.busyIds,
        requestedIds: requestedIds ?? this.requestedIds,
      );
}

class SuggestionsNotifier extends Notifier<SuggestionsState> {
  static const _pageSize = 10;

  NetworkRepository get _network => ref.read(networkRepositoryProvider);
  ConnectionsRepository get _connections =>
      ref.read(connectionsRepositoryProvider);

  // Stale-page guard: same pattern as PeopleNotifier._seq.
  // Incremented on every _loadFirst call; loadMore compares before committing results
  // so a concurrent refresh never interleaves with an in-flight page fetch.
  int _seq = 0;

  @override
  SuggestionsState build() {
    Future.microtask(_loadFirst);
    return const SuggestionsState(loading: true);
  }

  Future<void> refresh() => _loadFirst();

  Future<void> _loadFirst() async {
    final mySeq = ++_seq;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result =
          await _network.getSuggestions(page: 1, pageSize: _pageSize);
      if (mySeq != _seq) return;
      state = state.copyWith(
        items: result.items,
        page: result.page,
        hasNextPage: result.hasNextPage,
        loading: false,
      );
    } catch (e) {
      if (mySeq != _seq) return;
      state = state.copyWith(loading: false, error: _messageOf(e));
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasNextPage) return;
    final mySeq = _seq; // snapshot — do NOT increment; refresh must win
    state = state.copyWith(loadingMore: true);
    try {
      final next = state.page + 1;
      final result =
          await _network.getSuggestions(page: next, pageSize: _pageSize);
      if (mySeq != _seq) return;
      state = state.copyWith(
        items: [...state.items, ...result.items],
        page: result.page,
        hasNextPage: result.hasNextPage,
        loadingMore: false,
      );
    } catch (e) {
      if (mySeq != _seq) return;
      state = state.copyWith(loadingMore: false);
    }
  }

  // Connect — card switches to "Pending" on success and stays in the list.
  // invitesSentCount changes so overview must refresh.
  Future<String?> connect(String userId) async {
    if (state.busyIds.contains(userId)) return null;
    state = state.copyWith(busyIds: {...state.busyIds, userId});
    try {
      await _connections.sendRequest(userId);
      state = state.copyWith(
        requestedIds: {...state.requestedIds, userId},
        busyIds: {...state.busyIds}..remove(userId),
      );
      // invitesSentCount changed — refresh overview so network stats stay accurate
      ref.read(networkOverviewProvider.notifier).refresh();
      return null;
    } catch (e) {
      state = state.copyWith(busyIds: {...state.busyIds}..remove(userId));
      return _messageOf(e);
    }
  }

  // Dismissal removes the person from suggestions permanently (backend marks them dismissed).
  // This is destructive and must be reversible — that is why the DELETE /dismiss endpoint
  // and the Undo SnackBar affordance exist.
  Future<String?> dismiss(String userId) async {
    if (state.busyIds.contains(userId)) return null;
    state = state.copyWith(busyIds: {...state.busyIds, userId});
    try {
      await _network.dismissSuggestion(userId);
      state = state.copyWith(
        items: state.items.where((s) => s.userId != userId).toList(),
        busyIds: {...state.busyIds}..remove(userId),
      );
      return null;
    } catch (e) {
      state = state.copyWith(busyIds: {...state.busyIds}..remove(userId));
      return _messageOf(e);
    }
  }

  // Undo dismiss — calls DELETE /dismiss then reloads page 1.
  // Reload is the only reliable way to get the person back into the ranked list.
  Future<String?> undoDismiss(String userId) async {
    try {
      await _network.unDismissSuggestion(userId);
      await _loadFirst();
      return null;
    } catch (e) {
      return _messageOf(e);
    }
  }

  // Shared mapper — offline / session-expired / server / 4xx-detail alag messages.
  String _messageOf(Object e) => appErrorMessage(e);
}

final suggestionsProvider =
    NotifierProvider<SuggestionsNotifier, SuggestionsState>(
  SuggestionsNotifier.new,
);
