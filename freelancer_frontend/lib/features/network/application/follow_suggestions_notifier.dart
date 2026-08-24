import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../data/models/network_models.dart';
import '../data/network_repository.dart';
import 'network_overview_notifier.dart';

class FollowSuggestionsState {
  final List<FollowSuggestion> items;
  final int page;
  final bool hasNextPage;
  final bool loading;
  final bool loadingMore;
  final String? error;
  // Per-card in-flight guard (follow, unfollow, dismiss)
  final Set<String> busyIds;
  // Optimistic follow state — tracks which cards the user has followed this session.
  // Not stored in item data because suggestions endpoint returns un-followed people;
  // we maintain local flip state and revert on API failure.
  final Set<String> followedIds;

  const FollowSuggestionsState({
    this.items = const [],
    this.page = 0,
    this.hasNextPage = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.busyIds = const {},
    this.followedIds = const {},
  });

  FollowSuggestionsState copyWith({
    List<FollowSuggestion>? items,
    int? page,
    bool? hasNextPage,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool clearError = false,
    Set<String>? busyIds,
    Set<String>? followedIds,
  }) =>
      FollowSuggestionsState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasNextPage: hasNextPage ?? this.hasNextPage,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
        busyIds: busyIds ?? this.busyIds,
        followedIds: followedIds ?? this.followedIds,
      );
}

class FollowSuggestionsNotifier extends Notifier<FollowSuggestionsState> {
  static const _pageSize = 10;

  NetworkRepository get _network => ref.read(networkRepositoryProvider);

  // Stale-page guard — same pattern as SuggestionsNotifier and PeopleNotifier.
  // Increment on _loadFirst; loadMore snapshots without incrementing so a concurrent
  // refresh always wins and in-flight page results are safely discarded.
  int _seq = 0;

  @override
  FollowSuggestionsState build() {
    Future.microtask(_loadFirst);
    return const FollowSuggestionsState(loading: true);
  }

  Future<void> refresh() => _loadFirst();

  Future<void> _loadFirst() async {
    final mySeq = ++_seq;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result =
          await _network.getFollowSuggestions(page: 1, pageSize: _pageSize);
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
    final mySeq = _seq; // snapshot only — do NOT increment; refresh wins if concurrent
    state = state.copyWith(loadingMore: true);
    try {
      final next = state.page + 1;
      final result =
          await _network.getFollowSuggestions(page: next, pageSize: _pageSize);
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

  // Follow is OPTIMISTIC — unlike Connect (pessimistic) which sends a notification
  // that cannot be un-ghost-ed and requires approval. Follow is instantly reversible,
  // needs no approval, and the recipient is never notified of a transient follow+unfollow.
  // So we flip the button immediately and only revert on API failure.
  Future<String?> follow(String userId) async {
    if (state.busyIds.contains(userId)) return null;
    state = state.copyWith(
      busyIds: {...state.busyIds, userId},
      followedIds: {...state.followedIds, userId}, // optimistic flip
    );
    try {
      await _network.follow(userId);
      state = state.copyWith(busyIds: {...state.busyIds}..remove(userId));
      // followingCount changed — keep overview stats accurate
      ref.read(networkOverviewProvider.notifier).refresh();
      return null;
    } catch (e) {
      // Revert optimistic flip
      state = state.copyWith(
        busyIds: {...state.busyIds}..remove(userId),
        followedIds: {...state.followedIds}..remove(userId),
      );
      return _messageOf(e);
    }
  }

  // Unfollow is also OPTIMISTIC for the same reasons as follow above.
  Future<String?> unfollow(String userId) async {
    if (state.busyIds.contains(userId)) return null;
    state = state.copyWith(
      busyIds: {...state.busyIds, userId},
      followedIds: {...state.followedIds}..remove(userId), // optimistic flip
    );
    try {
      await _network.unfollow(userId);
      state = state.copyWith(busyIds: {...state.busyIds}..remove(userId));
      // followingCount changed — keep overview stats accurate
      ref.read(networkOverviewProvider.notifier).refresh();
      return null;
    } catch (e) {
      // Revert: re-add to followedIds
      state = state.copyWith(
        busyIds: {...state.busyIds}..remove(userId),
        followedIds: {...state.followedIds, userId},
      );
      return _messageOf(e);
    }
  }

  // Dismiss is PESSIMISTIC + Undo: removing someone permanently without their consent
  // is irreversible on the backend until undoDismiss is called, so we wait for API
  // confirmation before removing the card (no ghost card risk on failure).
  Future<String?> dismiss(String userId) async {
    if (state.busyIds.contains(userId)) return null;
    state = state.copyWith(busyIds: {...state.busyIds, userId});
    try {
      await _network.dismissFollowSuggestion(userId);
      state = state.copyWith(
        items: state.items.where((s) => s.userId != userId).toList(),
        busyIds: {...state.busyIds}..remove(userId),
        followedIds: {...state.followedIds}..remove(userId),
      );
      return null;
    } catch (e) {
      state = state.copyWith(busyIds: {...state.busyIds}..remove(userId));
      return _messageOf(e);
    }
  }

  // Undo dismiss: calls DELETE /dismiss then reloads page 1 to restore ranking.
  Future<String?> undoDismiss(String userId) async {
    try {
      await _network.unDismissFollowSuggestion(userId);
      await _loadFirst();
      return null;
    } catch (e) {
      return _messageOf(e);
    }
  }

  // Shared mapper — offline / session-expired / server / 4xx-detail alag messages.
  String _messageOf(Object e) => appErrorMessage(e);
}

final followSuggestionsProvider =
    NotifierProvider<FollowSuggestionsNotifier, FollowSuggestionsState>(
  FollowSuggestionsNotifier.new,
);
