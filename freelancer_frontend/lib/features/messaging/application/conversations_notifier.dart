import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/realtime_notifier.dart';
import '../data/messaging_repository.dart';
import '../data/models/messaging_models.dart';
import 'active_conversation_provider.dart';

// Accepted conversations list — page 1 load, infinite scroll, pull-to-refresh.
// Bilkul PeopleNotifier ke pattern pe (search ke bagair — is list mein search nahi).
class ConversationsState {
  final List<ConversationSummary> items;
  final int page; // aakhri load hui page
  final bool hasMore;
  final bool isLoading; // pehli load / refresh
  final bool isLoadingMore; // next page append
  final bool loadMoreFailed; // list ke neeche inline retry dikhane ke liye
  final String? error; // pehli load fail (full-screen retry)

  const ConversationsState({
    this.items = const [],
    this.page = 0,
    this.hasMore = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.error,
  });

  ConversationsState copyWith({
    List<ConversationSummary>? items,
    int? page,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    bool? loadMoreFailed,
    String? error,
    bool clearError = false,
  }) =>
      ConversationsState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
        error: clearError ? null : (error ?? this.error),
      );
}

// Riverpod 3 Notifier (StateProvider legacy — use nahi karna).
class ConversationsNotifier extends Notifier<ConversationsState> {
  static const _pageSize = 20;

  MessagingRepository get _repo => ref.read(messagingRepositoryProvider);

  // Stale-response guard (PeopleNotifier._seq): har fresh load is seq ko badhata
  // hai; slow page-2 ka jawab fresh refresh ko overwrite na kar de.
  int _seq = 0;
  Timer? _reconnectDebounce;

  @override
  ConversationsState build() {
    final client = ref.read(realtimeClientProvider);

    final msgSub = client.events
        .where((e) => e.name == 'MessageReceived')
        .listen(_onMessageReceived);

    final acceptedSub = client.events
        .where((e) => e.name == 'ConversationAccepted')
        .listen(_onConversationAccepted);

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
      msgSub.cancel();
      acceptedSub.cancel();
      _reconnectDebounce?.cancel();
    });

    Future.microtask(_loadFirst);
    return const ConversationsState(isLoading: true);
  }

  // Pull-to-refresh — page 1 se dobara
  Future<void> refresh() => _loadFirst();

  Future<void> _loadFirst() async {
    final mySeq = ++_seq;
    state = state.copyWith(
      isLoading: true,
      loadMoreFailed: false,
      clearError: true,
    );
    try {
      final result = await _repo.getConversations(page: 1, pageSize: _pageSize);
      if (mySeq != _seq) return; // beech mein naya refresh aa gaya — chhodo
      state = state.copyWith(
        items: result.items,
        page: result.page,
        hasMore: result.hasNextPage,
        isLoading: false,
      );
    } catch (e) {
      if (mySeq != _seq) return;
      state = state.copyWith(isLoading: false, error: _messageOf(e));
    }
  }

  // Infinite scroll — agli page append. Double-fetch guard + stale-page guard.
  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !state.hasMore) return;

    final mySeq = _seq; // isi load ke andar rehna chahiye (increment NAHI)
    state = state.copyWith(isLoadingMore: true, loadMoreFailed: false);
    try {
      final next = state.page + 1;
      final result =
          await _repo.getConversations(page: next, pageSize: _pageSize);
      if (mySeq != _seq) return; // beech mein refresh — ye page stale hai
      state = state.copyWith(
        items: [...state.items, ...result.items],
        page: result.page,
        hasMore: result.hasNextPage,
        isLoadingMore: false,
      );
    } catch (_) {
      if (mySeq != _seq) return;
      // Items preserve; neeche inline retry dikhega
      state = state.copyWith(isLoadingMore: false, loadMoreFailed: true);
    }
  }

  // ── Hub event handlers ────────────────────────────────────────────────────

  void _onMessageReceived(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    final senderId = e.payload['senderId'] as String?;
    final body = e.payload['body'] as String?;
    final createdAtRaw = e.payload['createdAt'] as String?;
    if (convId == null || body == null || createdAtRaw == null) return;

    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) return;

    // If the conversation is already in the list: patch it in place (update preview,
    // reorder to top, increment unread if sender is the other person and chat not open).
    // If the conversation is not in the list: refetch page 1 — a new accepted thread
    // may have appeared (e.g. message sent before this device saw the acceptance).
    final idx = state.items.indexWhere((c) => c.id == convId);
    if (idx == -1) {
      _loadFirst();
      return;
    }

    final existing = state.items[idx];
    // sender == otherUser.userId → message is from them; else it's ours.
    // Don't increment unread count if the user is actively reading the conversation.
    final isFromOther = senderId == existing.otherUser.userId;
    final chatIsOpen = ref.read(activeConversationProvider) == convId;
    final newUnread = isFromOther && !chatIsOpen
        ? existing.unreadCount + 1
        : existing.unreadCount;

    final preview = body.length > 120 ? '${body.substring(0, 120)}…' : body;
    final updated = ConversationSummary(
      id: existing.id,
      status: existing.status,
      isRequest: existing.isRequest,
      otherUser: existing.otherUser,
      lastMessagePreview: preview,
      lastMessageAt: createdAt, // UTC; render pe .toLocal()
      unreadCount: newUnread,
    );
    // Move to top of list (newest conversation first).
    state = state.copyWith(items: [
      updated,
      ...state.items.where((c) => c.id != convId),
    ]);
  }

  void _onConversationAccepted(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    if (convId == null) return;
    final idx = state.items.indexWhere((c) => c.id == convId);
    if (idx == -1) return;
    final existing = state.items[idx];
    // Transition the initiator's pending tile to accepted — removes "Request sent" label.
    final updated = ConversationSummary(
      id: existing.id,
      status: ConversationStatus.accepted,
      isRequest: false,
      otherUser: existing.otherUser,
      lastMessagePreview: existing.lastMessagePreview,
      lastMessageAt: existing.lastMessageAt,
      unreadCount: existing.unreadCount,
    );
    final newItems = List<ConversationSummary>.from(state.items);
    newItems[idx] = updated;
    state = state.copyWith(items: newItems);
  }

  // Debounce reconnect refresh: flapping connectivity triggers one refresh per window.
  void _scheduleReconnectRefresh() {
    _reconnectDebounce?.cancel();
    _reconnectDebounce = Timer(const Duration(seconds: 3), _loadFirst);
  }

  // Shared mapper — offline / session-expired / server / 4xx-detail alag messages.
  String _messageOf(Object e) => appErrorMessage(e);
}

final conversationsProvider =
    NotifierProvider<ConversationsNotifier, ConversationsState>(
        ConversationsNotifier.new);
