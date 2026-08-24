import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../connections/data/connections_repository.dart';
import '../../connections/data/models/connection_models.dart';
import '../data/models/person_model.dart';
import '../data/people_repository.dart';

// People screen ka poora state — list + pagination + search + flags.
class PeopleState {
  final String search;
  final List<PersonModel> items;
  final int page; // aakhri load hui page
  final bool hasNextPage;
  final bool loading; // pehli load / search reset / pull-to-refresh
  final bool loadingMore; // next page append ho raha hai
  final String? error; // initial load fail (retry ke liye)

  // Jin rows ki sendConnect call in-flight hai — SIRF wahi button spinner
  // dikhata + disable hota hai; baqi list azad.
  final Set<String> connectingIds;

  const PeopleState({
    this.search = '',
    this.items = const [],
    this.page = 0,
    this.hasNextPage = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.connectingIds = const {},
  });

  PeopleState copyWith({
    String? search,
    List<PersonModel>? items,
    int? page,
    bool? hasNextPage,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool clearError = false,
    Set<String>? connectingIds,
  }) =>
      PeopleState(
        search: search ?? this.search,
        items: items ?? this.items,
        page: page ?? this.page,
        hasNextPage: hasNextPage ?? this.hasNextPage,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
        connectingIds: connectingIds ?? this.connectingIds,
      );
}

// Riverpod 3 Notifier (StateProvider legacy — use nahi karna).
class PeopleNotifier extends Notifier<PeopleState> {
  static const _pageSize = 20;

  PeopleRepository get _people => ref.read(peopleRepositoryProvider);
  ConnectionsRepository get _connections =>
      ref.read(connectionsRepositoryProvider);

  Timer? _debounce;
  // Stale-response guard: har naya search/refresh is seq ko badhata hai;
  // purani in-flight call ka jawab aaye to seq mismatch pe ignore.
  int _seq = 0;

  @override
  PeopleState build() {
    // Notifier dispose pe pending timer bhi saaf (username-screen wala pattern)
    ref.onDispose(() => _debounce?.cancel());
    // Pehli load bina search ke
    Future.microtask(_loadFirst);
    return const PeopleState(loading: true);
  }

  // Search field se har keystroke — 500ms khamoshi ke baad hi reload (username
  // availability wala debounce pattern). Reset to page 1.
  void onSearchChanged(String value) {
    state = state.copyWith(search: value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _loadFirst);
  }

  // Pull-to-refresh — abhi wali search ke sath page 1 se dobara
  Future<void> refresh() => _loadFirst();

  // Page 1 (fresh) — initial, search change, aur refresh teenon isi se
  Future<void> _loadFirst() async {
    final mySeq = ++_seq; // is call ka token
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _people.getPeople(
        search: state.search,
        page: 1,
        pageSize: _pageSize,
      );
      if (mySeq != _seq) return; // beech mein naya search/refresh aa gaya — chhodo
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

  // Infinite scroll — list ke neeche pahunchne pe agli page. Double-fetch guard:
  // agar pehle se loadingMore/loading hai ya aur pages nahi, to kuch mat karo.
  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasNextPage) return;

    final mySeq = _seq; // isi search ke andar rehna chahiye
    state = state.copyWith(loadingMore: true);
    try {
      final next = state.page + 1;
      final result = await _people.getPeople(
        search: state.search,
        page: next,
        pageSize: _pageSize,
      );
      // Beech mein search/refresh ho gaya to ye page stale hai — mat jodo
      if (mySeq != _seq) return;
      state = state.copyWith(
        items: [...state.items, ...result.items],
        page: result.page,
        hasNextPage: result.hasNextPage,
        loadingMore: false,
      );
    } catch (e) {
      if (mySeq != _seq) return;
      // loadMore fail — silently stop spinner; user dobara scroll/refresh kar sakta
      state = state.copyWith(loadingMore: false);
    }
  }

  // PESSIMISTIC connect: API pehle, success pe hi row ka status
  // PendingOutgoing karo. Fail pe row waisa hi — caller SnackBar dikhata hai.
  // Return: null = success, warna error message.
  Future<String?> sendConnect(String userId) async {
    if (state.connectingIds.contains(userId)) return null; // double-tap guard

    state = state.copyWith(connectingIds: {...state.connectingIds, userId});
    try {
      await _connections.sendRequest(userId); // REUSE — naya method nahi
      state = state.copyWith(
        items: state.items
            .map((p) => p.userId == userId
                ? p.copyWith(
                    connectionStatus: ConnectionStatusWith.pendingOutgoing)
                : p)
            .toList(),
        connectingIds: {...state.connectingIds}..remove(userId),
      );
      return null;
    } catch (e) {
      state =
          state.copyWith(connectingIds: {...state.connectingIds}..remove(userId));
      return _messageOf(e);
    }
  }

  // Backend ProblemDetails ka 'detail' — baqi screens wala pattern
  // Shared mapper — offline / session-expired / server / 4xx-detail alag messages.
  String _messageOf(Object e) => appErrorMessage(e);
}

final peopleProvider =
    NotifierProvider<PeopleNotifier, PeopleState>(PeopleNotifier.new);
