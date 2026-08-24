import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/models/paged_result.dart';
import '../../network/application/network_overview_notifier.dart';
import '../data/connections_repository.dart';
import '../data/models/connection_models.dart';

// ── Per-tab paged state ────────────────────────────────────────────────────────

class InvitationsTabState {
  final List<PendingRequest> items;
  final int page;
  final bool hasMore;
  final bool isLoadingMore;
  // totalCount from the PagedResult envelope — reliable total regardless of
  // how many pages have been loaded (items.length is capped by pageSize).
  final int totalCount;
  final String? error;

  const InvitationsTabState({
    this.items = const [],
    this.page = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.totalCount = 0,
    this.error,
  });

  InvitationsTabState copyWith({
    List<PendingRequest>? items,
    int? page,
    bool? hasMore,
    bool? isLoadingMore,
    int? totalCount,
    String? error,
    bool clearError = false,
  }) =>
      InvitationsTabState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        totalCount: totalCount ?? this.totalCount,
        error: clearError ? null : (error ?? this.error),
      );
}

// ── Top-level state ────────────────────────────────────────────────────────────

class InvitationsState {
  final bool loading; // true only during the initial parallel load
  final InvitationsTabState received;
  final InvitationsTabState sent;
  // Per-card in-flight guard — shared across tabs (a request exists in one tab only)
  final Set<String> busyIds;

  const InvitationsState({
    this.loading = false,
    this.received = const InvitationsTabState(),
    this.sent = const InvitationsTabState(),
    this.busyIds = const {},
  });

  // Backward-compat getters used by InvitesReceivedSection (home preview)
  List<PendingRequest> get incoming => received.items;
  String? get error => received.error;

  InvitationsState copyWith({
    bool? loading,
    InvitationsTabState? received,
    InvitationsTabState? sent,
    Set<String>? busyIds,
  }) =>
      InvitationsState(
        loading: loading ?? this.loading,
        received: received ?? this.received,
        sent: sent ?? this.sent,
        busyIds: busyIds ?? this.busyIds,
      );
}

// ── Notifier ───────────────────────────────────────────────────────────────────

class InvitationsNotifier extends Notifier<InvitationsState> {
  static const _pageSize = 20;

  ConnectionsRepository get _repo => ref.read(connectionsRepositoryProvider);

  // Stale-page guards — one per tab, same pattern as PeopleNotifier._seq.
  // Incremented on _loadFirstX; loadMoreX snapshots without incrementing so a
  // tab switch or pull-to-refresh mid-flight cannot append stale pages.
  int _seqR = 0;
  int _seqS = 0;

  @override
  InvitationsState build() {
    Future.microtask(load);
    return const InvitationsState(loading: true);
  }

  // Loads page 1 of both tabs in parallel. Independent per-tab error handling
  // ensures one tab erroring does not blank the other (spec requirement).
  Future<void> load() async {
    final seqR = ++_seqR;
    final seqS = ++_seqS;
    state = state.copyWith(
      loading: true,
      received: state.received.copyWith(clearError: true),
      sent: state.sent.copyWith(clearError: true),
    );

    PagedResult<PendingRequest>? rResult;
    PagedResult<PendingRequest>? sResult;
    String? rError;
    String? sError;

    await Future.wait([
      _fetchTab(
        call: () => _repo.getIncoming(page: 1, pageSize: _pageSize),
        onResult: (r) => rResult = r,
        onError: (msg) => rError = msg,
      ),
      _fetchTab(
        call: () => _repo.getOutgoing(page: 1, pageSize: _pageSize),
        onResult: (r) => sResult = r,
        onError: (msg) => sError = msg,
      ),
    ]);

    if (_seqR != seqR || _seqS != seqS) return;

    state = state.copyWith(
      loading: false,
      received: rResult != null
          ? state.received.copyWith(
              items: rResult!.items,
              page: rResult!.page,
              hasMore: rResult!.hasNextPage,
              totalCount: rResult!.totalCount,
              clearError: true,
            )
          : state.received.copyWith(error: rError),
      sent: sResult != null
          ? state.sent.copyWith(
              items: sResult!.items,
              page: sResult!.page,
              hasMore: sResult!.hasNextPage,
              totalCount: sResult!.totalCount,
              clearError: true,
            )
          : state.sent.copyWith(error: sError),
    );
  }

  Future<void> _fetchTab({
    required Future<PagedResult<PendingRequest>> Function() call,
    required void Function(PagedResult<PendingRequest>) onResult,
    required void Function(String) onError,
  }) async {
    try {
      onResult(await call());
    } catch (e) {
      onError(_messageOf(e));
    }
  }

  Future<void> loadMoreIncoming() async {
    final tab = state.received;
    if (state.loading || tab.isLoadingMore || !tab.hasMore) return;
    final mySeq = _seqR; // snapshot only — do NOT increment; load() wins if concurrent
    final nextPage = tab.page + 1;
    state = state.copyWith(received: tab.copyWith(isLoadingMore: true));
    try {
      final result = await _repo.getIncoming(page: nextPage, pageSize: _pageSize);
      if (mySeq != _seqR) return;
      state = state.copyWith(
        received: state.received.copyWith(
          items: [...state.received.items, ...result.items],
          page: result.page,
          hasMore: result.hasNextPage,
          totalCount: result.totalCount,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (mySeq != _seqR) return;
      state = state.copyWith(received: state.received.copyWith(isLoadingMore: false));
    }
  }

  Future<void> loadMoreOutgoing() async {
    final tab = state.sent;
    if (state.loading || tab.isLoadingMore || !tab.hasMore) return;
    final mySeq = _seqS;
    final nextPage = tab.page + 1;
    state = state.copyWith(sent: tab.copyWith(isLoadingMore: true));
    try {
      final result = await _repo.getOutgoing(page: nextPage, pageSize: _pageSize);
      if (mySeq != _seqS) return;
      state = state.copyWith(
        sent: state.sent.copyWith(
          items: [...state.sent.items, ...result.items],
          page: result.page,
          hasMore: result.hasNextPage,
          totalCount: result.totalCount,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (mySeq != _seqS) return;
      state = state.copyWith(sent: state.sent.copyWith(isLoadingMore: false));
    }
  }

  // PESSIMISTIC: API first, then remove card + decrement totalCount.
  // overview refresh here (not in widgets) so it fires regardless of which
  // screen (home preview or invitations screen) triggered the action.
  Future<String?> accept(String connectionId) =>
      _act(connectionId, () => _repo.acceptRequest(connectionId), fromReceived: true);

  Future<String?> reject(String connectionId) =>
      _act(connectionId, () => _repo.rejectRequest(connectionId), fromReceived: true);

  Future<String?> withdraw(String connectionId) =>
      _act(connectionId, () => _repo.withdrawRequest(connectionId), fromReceived: false);

  Future<String?> _act(
    String connectionId,
    Future<void> Function() call, {
    required bool fromReceived,
  }) async {
    if (state.busyIds.contains(connectionId)) return null;
    state = state.copyWith(busyIds: {...state.busyIds, connectionId});
    try {
      await call();
      if (fromReceived) {
        state = state.copyWith(
          received: state.received.copyWith(
            items: state.received.items
                .where((r) => r.connectionId != connectionId)
                .toList(),
            totalCount:
                (state.received.totalCount - 1).clamp(0, state.received.totalCount),
          ),
          busyIds: {...state.busyIds}..remove(connectionId),
        );
      } else {
        state = state.copyWith(
          sent: state.sent.copyWith(
            items: state.sent.items
                .where((r) => r.connectionId != connectionId)
                .toList(),
            totalCount:
                (state.sent.totalCount - 1).clamp(0, state.sent.totalCount),
          ),
          busyIds: {...state.busyIds}..remove(connectionId),
        );
      }
      // accept/reject → connectionsCount + invitesReceivedCount changed.
      // withdraw → invitesSentCount changed. Refresh so overview stats stay accurate.
      ref.read(networkOverviewProvider.notifier).refresh();
      return null;
    } catch (e) {
      state = state.copyWith(busyIds: {...state.busyIds}..remove(connectionId));
      return _messageOf(e);
    }
  }

  // Shared mapper — offline / session-expired / server / 4xx-detail alag messages.
  String _messageOf(Object e) => appErrorMessage(e);
}

final invitationsProvider =
    NotifierProvider<InvitationsNotifier, InvitationsState>(
        InvitationsNotifier.new);
