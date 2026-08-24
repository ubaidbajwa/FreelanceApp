import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/realtime_notifier.dart';
import '../data/messaging_repository.dart';
import '../data/models/messaging_models.dart';
import 'conversations_notifier.dart';

// Incoming pending message-requests list — same shape jaisa ConversationsNotifier,
// plus accept/decline (InvitationsNotifier ka pessimistic per-row pattern).
class ConversationRequestsState {
  final List<ConversationSummary> items;
  final int page;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  final String? error;
  // Envelope ka totalCount — tab badge (Requests · N) yahi dikhata hai,
  // chahe kitni bhi pages load hui hon.
  final int pendingCount;
  // Per-row accept/decline in-flight guard — sirf tapped card spinner dikhata hai.
  final Set<String> busyIds;

  const ConversationRequestsState({
    this.items = const [],
    this.page = 0,
    this.hasMore = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.error,
    this.pendingCount = 0,
    this.busyIds = const {},
  });

  ConversationRequestsState copyWith({
    List<ConversationSummary>? items,
    int? page,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    bool? loadMoreFailed,
    String? error,
    bool clearError = false,
    int? pendingCount,
    Set<String>? busyIds,
  }) =>
      ConversationRequestsState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
        error: clearError ? null : (error ?? this.error),
        pendingCount: pendingCount ?? this.pendingCount,
        busyIds: busyIds ?? this.busyIds,
      );
}

// Riverpod 3 Notifier (StateProvider legacy — use nahi karna).
class ConversationRequestsNotifier
    extends Notifier<ConversationRequestsState> {
  static const _pageSize = 20;

  MessagingRepository get _repo => ref.read(messagingRepositoryProvider);

  int _seq = 0;
  Timer? _reconnectDebounce;

  @override
  ConversationRequestsState build() {
    final client = ref.read(realtimeClientProvider);

    final reqSub = client.events
        .where((e) => e.name == 'ConversationRequestReceived')
        .listen(_onRequestReceived);

    // Reconnect gap: refetch when hub reconnects (not on first connect — no gap then).
    // Guard against a reconnect storm: debounce so flapping fires one refresh, not N.
    //
    // Baseline is per-notifier-lifetime: the global connectCount is monotonic,
    // so `> 1` is permanently true after the app's first reconnect and caused
    // spurious refetches. Gap only exists if a connect landed AFTER this
    // notifier's initial load — count above the baseline. `count > 1` keeps
    // the app's very first connect from triggering (no gap by definition).
    final baselineConnectCount =
        ref.read(realtimeNotifierProvider.notifier).connectCount;
    ref.listen<RealtimeConnectionState>(realtimeNotifierProvider, (_, next) {
      final count = ref.read(realtimeNotifierProvider.notifier).connectCount;
      if (next == RealtimeConnectionState.connected &&
          count > baselineConnectCount &&
          count > 1) {
        _scheduleReconnectRefresh();
      }
    });

    ref.onDispose(() {
      reqSub.cancel();
      _reconnectDebounce?.cancel();
    });

    Future.microtask(_loadFirst);
    return const ConversationRequestsState(isLoading: true);
  }

  Future<void> refresh() => _loadFirst();

  Future<void> _loadFirst() async {
    final mySeq = ++_seq;
    state = state.copyWith(
      isLoading: true,
      loadMoreFailed: false,
      clearError: true,
    );
    try {
      final result = await _repo.getRequests(page: 1, pageSize: _pageSize);
      if (mySeq != _seq) return;
      state = state.copyWith(
        items: result.items,
        page: result.page,
        hasMore: result.hasNextPage,
        pendingCount: result.totalCount,
        isLoading: false,
      );
    } catch (e) {
      if (mySeq != _seq) return;
      state = state.copyWith(isLoading: false, error: _messageOf(e));
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !state.hasMore) return;

    final mySeq = _seq;
    state = state.copyWith(isLoadingMore: true, loadMoreFailed: false);
    try {
      final next = state.page + 1;
      final result = await _repo.getRequests(page: next, pageSize: _pageSize);
      if (mySeq != _seq) return;
      state = state.copyWith(
        items: [...state.items, ...result.items],
        page: result.page,
        hasMore: result.hasNextPage,
        pendingCount: result.totalCount,
        isLoadingMore: false,
      );
    } catch (_) {
      if (mySeq != _seq) return;
      state = state.copyWith(isLoadingMore: false, loadMoreFailed: true);
    }
  }

  // ── Hub event handlers ────────────────────────────────────────────────────

  void _onRequestReceived(RealtimeEvent e) {
    try {
      final summary = ConversationSummary.fromJson(e.payload);
      // Dedupe: if already in list (e.g. duplicate event or reconnect storm), ignore.
      if (state.items.any((c) => c.id == summary.id)) return;
      state = state.copyWith(
        items: [summary, ...state.items],
        pendingCount: state.pendingCount + 1,
      );
    } catch (_) {
      // Malformed payload — ignore; refetch on next reconnect will correct.
    }
  }

  // Debounce reconnect refresh: flapping connectivity triggers one refresh per window.
  void _scheduleReconnectRefresh() {
    _reconnectDebounce?.cancel();
    _reconnectDebounce = Timer(const Duration(seconds: 3), _loadFirst);
  }

  // PESSIMISTIC accept: API pehle, phir row hatao + pendingCount ghatao.
  // Success pe thread accepted list mein chali jati hai → ConversationsNotifier
  // refresh taake wahan reappear ho. Return: null=success, warna error message.
  Future<String?> accept(String conversationId) => _act(
        conversationId,
        () => _repo.acceptConversation(conversationId),
        refreshConversations: true,
      );

  // PESSIMISTIC decline: row hatao. Accepted list ko HAATH nahi lagana.
  Future<String?> decline(String conversationId) => _act(
        conversationId,
        () => _repo.declineConversation(conversationId),
        refreshConversations: false,
      );

  Future<String?> _act(
    String conversationId,
    Future<void> Function() call, {
    required bool refreshConversations,
  }) async {
    if (state.busyIds.contains(conversationId)) return null; // double-tap guard
    state = state.copyWith(busyIds: {...state.busyIds, conversationId});
    try {
      await call();
      state = state.copyWith(
        items:
            state.items.where((c) => c.id != conversationId).toList(),
        pendingCount: (state.pendingCount - 1).clamp(0, state.pendingCount),
        busyIds: {...state.busyIds}..remove(conversationId),
      );
      if (refreshConversations) {
        ref.read(conversationsProvider.notifier).refresh();
      }
      return null;
    } catch (e) {
      // Fail pe row waisa hi rehta hai (phantom removal nahi) — caller SnackBar dikhata
      state =
          state.copyWith(busyIds: {...state.busyIds}..remove(conversationId));
      return _messageOf(e);
    }
  }

  // Shared mapper — offline / session-expired / server / 4xx-detail alag messages.
  String _messageOf(Object e) => appErrorMessage(e);
}

final conversationRequestsProvider =
    NotifierProvider<ConversationRequestsNotifier, ConversationRequestsState>(
        ConversationRequestsNotifier.new);
