// ChatNotifier unit tests — silent-failure paths identified in the F-M3b audit.
//
// These tests do NOT boot Flutter (no WidgetTester). They exercise the Riverpod
// notifier directly via ProviderContainer so bugs that are invisible to the UI
// (isLoading stuck, stale-discard stranding the spinner) are caught here instead.
//
// Five scenarios (all previously untested, flagged in docs/TODO.md):
//   1. Successful load → isLoading clears
//   2. Failed load    → isLoading clears + error set
//   3. Empty result   → isLoading clears (no permanent spinner)
//   4. Stale-discard  → isLoading clears via the newer open()'s finally
//   5. Reconnect race → refetch blocked until initial load completes; no spinner

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:freelancer_frontend/core/models/paged_result.dart';
import 'package:freelancer_frontend/core/realtime/realtime_client.dart';
import 'package:freelancer_frontend/core/realtime/realtime_notifier.dart';
import 'package:freelancer_frontend/features/messaging/application/chat_notifier.dart';
import 'package:freelancer_frontend/features/messaging/data/messaging_repository.dart';
import 'package:freelancer_frontend/features/messaging/data/models/messaging_models.dart';

// ── Fakes ───────────────────────────────────────────────────────────────────

// Broadcast-stream fake — controllable from tests.
class _FakeRealtimeClient implements RealtimeClient {
  final _stateCtrl = StreamController<RealtimeConnectionState>.broadcast();
  final _eventsCtrl = StreamController<RealtimeEvent>.broadcast();

  @override
  Stream<RealtimeConnectionState> get connectionState => _stateCtrl.stream;
  @override
  Stream<RealtimeEvent> get events => _eventsCtrl.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  void dispose() {
    _stateCtrl.close();
    _eventsCtrl.close();
  }

  void emitState(RealtimeConnectionState s) => _stateCtrl.add(s);
  void emitEvent(RealtimeEvent e) => _eventsCtrl.add(e);
}

// Queue-based fake — enqueue futures before they're needed.
class _FakeRepo implements MessagingRepository {
  final _msgQueue = <Future<MessagePage>>[];
  int getMessagesCallCount = 0;

  // ── F-M7 reaction controls ────────────────────────────────────────────────
  int reactCallCount = 0;
  int removeCallCount = 0;
  bool reactShouldFail = false; // next react/remove throws
  Completer<List<MessageReaction>>? reactGate; // hold react in flight if set

  void enqueue(Future<MessagePage> f) => _msgQueue.add(f);

  @override
  Future<MessagePage> getMessages(String conversationId,
      {DateTime? before, int limit = 30}) {
    getMessagesCallCount++;
    if (_msgQueue.isNotEmpty) return _msgQueue.removeAt(0);
    return Future.value(const MessagePage(items: [], hasMore: false));
  }

  @override
  Future<void> markRead(String conversationId) async {}

  @override
  Future<PagedResult<ConversationSummary>> getConversations(
          {int page = 1, int pageSize = 20}) async =>
      const PagedResult(
          items: [],
          page: 1,
          pageSize: 20,
          totalCount: 0,
          totalPages: 0,
          hasNextPage: false);

  @override
  Future<PagedResult<ConversationSummary>> getRequests(
          {int page = 1, int pageSize = 20}) async =>
      const PagedResult(
          items: [],
          page: 1,
          pageSize: 20,
          totalCount: 0,
          totalPages: 0,
          hasNextPage: false);

  @override
  Future<ConversationSummary> startOrGetConversation(String recipientId) =>
      Future.error(UnimplementedError());

  @override
  Future<Message> sendMessage(String conversationId, String body,
          {String? replyToMessageId}) =>
      Future.error(UnimplementedError());

  @override
  Future<Message> sendMediaMessage(String conversationId, String filePath,
          {String? caption,
          String? replyToMessageId,
          String? waveform,
          void Function(int, int)? onSendProgress,
          CancelToken? cancelToken}) =>
      Future.error(UnimplementedError());

  @override
  Future<void> acceptConversation(String conversationId) async {}

  @override
  Future<void> declineConversation(String conversationId) async {}

  @override
  Future<ConversationSummary> getConversation(String conversationId) =>
      Future.error(UnimplementedError());

  // ── M2 message actions (unused by these tests) ────────────────────────────
  @override
  Future<void> deleteMessage(String c, String m, {required String scope}) async {}
  @override
  Future<void> pinMessage(String c, String m,
      {required PinDuration duration, bool replaceOldest = false}) async {}
  @override
  Future<void> unpinMessage(String c, String m) async {}
  @override
  Future<List<Message>> getPinnedMessages(String c) async => [];
  @override
  Future<List<MessageReaction>> reactToMessage(String c, String m, String e) async {
    reactCallCount++;
    if (reactShouldFail) throw Exception('react failed');
    if (reactGate != null) return reactGate!.future;
    // Server returns the caller-relative aggregate: the caller now owns this emoji.
    return [MessageReaction(emoji: e, count: 1, reactedByMe: true)];
  }

  @override
  Future<void> removeReaction(String c, String m) async {
    removeCallCount++;
    if (reactShouldFail) throw Exception('remove failed');
  }
  @override
  Future<Message> editMessage(String c, String m, String b) =>
      Future.error(UnimplementedError());
  @override
  Future<List<Message>> forwardMessages(String c,
          {required String targetConversationId,
          required List<String> messageIds}) async =>
      [];
}

// ── Helpers ─────────────────────────────────────────────────────────────────

ConversationSummary _summary({int unreadCount = 0, DateTime? otherLastReadAt}) =>
    ConversationSummary(
      id: 'conv1',
      status: ConversationStatus.accepted,
      isRequest: false,
      otherUser: const ConversationUser(userId: 'u2', fullName: 'Test User'),
      unreadCount: unreadCount,
      otherLastReadAt: otherLastReadAt,
    );

Message _msg(String id) => Message(
      id: id,
      conversationId: 'conv1',
      senderId: 'u2',
      body: 'hello',
      type: MessageType.text,
      createdAt: DateTime.utc(2025, 1, 1),
    );

MessagePage _page(List<Message> items) =>
    MessagePage(items: items, hasMore: false);

ProviderContainer _makeContainer(
  _FakeRepo repo, {
  _FakeRealtimeClient? client,
}) {
  final fakeClient = client ?? _FakeRealtimeClient();
  return ProviderContainer(
    overrides: [
      realtimeClientProvider.overrideWithValue(fakeClient),
      messagingRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  test('1. successful load clears isLoading', () async {
    final repo = _FakeRepo();
    final c = Completer<MessagePage>();
    repo.enqueue(c.future);

    final container = _makeContainer(repo);
    container.listen(chatProvider, (_, _) {}); // keep autoDispose provider alive
    addTearDown(container.dispose);

    final notifier = container.read(chatProvider.notifier);
    notifier.open(conversationId: 'conv1', summary: _summary());
    await Future<void>.delayed(Duration.zero);

    expect(container.read(chatProvider).isLoading, isTrue,
        reason: 'spinner while fetch is in flight');

    c.complete(_page([_msg('m1'), _msg('m2')]));
    await Future<void>.delayed(Duration.zero);

    final s = container.read(chatProvider);
    expect(s.isLoading, isFalse, reason: 'isLoading must clear after success');
    expect(s.error, isNull);
    expect(s.messages, hasLength(2));
  });

  test('2. failed load clears isLoading and exposes error', () async {
    final repo = _FakeRepo();
    final c = Completer<MessagePage>();
    repo.enqueue(c.future);

    final container = _makeContainer(repo);
    container.listen(chatProvider, (_, _) {}); // keep autoDispose provider alive
    addTearDown(container.dispose);

    final notifier = container.read(chatProvider.notifier);
    notifier.open(conversationId: 'conv1', summary: _summary());
    await Future<void>.delayed(Duration.zero);

    c.completeError(Exception('network error'));
    await Future<void>.delayed(Duration.zero);

    final s = container.read(chatProvider);
    expect(s.isLoading, isFalse, reason: 'isLoading must clear even on error');
    expect(s.error, isNotNull, reason: 'error message should be set');
    expect(s.messages, isEmpty);
  });

  test('3. empty result clears isLoading (not a permanent spinner)', () async {
    final repo = _FakeRepo();
    final c = Completer<MessagePage>();
    repo.enqueue(c.future);

    final container = _makeContainer(repo);
    container.listen(chatProvider, (_, _) {}); // keep autoDispose provider alive
    addTearDown(container.dispose);

    final notifier = container.read(chatProvider.notifier);
    notifier.open(conversationId: 'conv1', summary: _summary());
    await Future<void>.delayed(Duration.zero);

    c.complete(_page([])); // zero messages
    await Future<void>.delayed(Duration.zero);

    final s = container.read(chatProvider);
    expect(s.isLoading, isFalse,
        reason: 'empty response must not leave spinner');
    expect(s.messages, isEmpty);
    expect(s.error, isNull);
    // chat_screen shows chatEmpty text when isLoading=false && messages.isEmpty
  });

  test('4. stale-discarded response does not leave isLoading true', () async {
    final repo = _FakeRepo();
    final c1 = Completer<MessagePage>(); // first open's fetch
    final c2 = Completer<MessagePage>(); // second open's fetch
    repo.enqueue(c1.future);
    repo.enqueue(c2.future);

    final container = _makeContainer(repo);
    container.listen(chatProvider, (_, _) {}); // keep autoDispose provider alive
    addTearDown(container.dispose);

    final notifier = container.read(chatProvider.notifier);

    // First open (seq=1) — starts, awaiting c1
    notifier.open(conversationId: 'conv1', summary: _summary());
    await Future<void>.delayed(Duration.zero);

    // Second open (seq=2) — bumps _seq; c1 response will be stale
    notifier.open(conversationId: 'conv1', summary: _summary());
    await Future<void>.delayed(Duration.zero);

    // Resolve first (stale) response: mySeq(1) != _seq(2) → stale guard fires
    c1.complete(_page([_msg('m1')]));
    await Future<void>.delayed(Duration.zero);

    // isLoading is still true — the second open is in flight and owns it
    expect(container.read(chatProvider).isLoading, isTrue,
        reason: 'second open is in flight; isLoading belongs to it');

    // Resolve second (current) response → isLoading clears via second finally
    c2.complete(_page([_msg('m2')]));
    await Future<void>.delayed(Duration.zero);

    final s = container.read(chatProvider);
    expect(s.isLoading, isFalse,
        reason: 'second open finally clears isLoading after stale discard');
    expect(s.messages, hasLength(1)); // only m2 (second open's response)
  });

  test('5. reconnect refetch is blocked until initial load completes', () {
    // Uses fakeAsync so the 3-second debounce timer can be advanced without
    // actually waiting in CI.
    fakeAsync((async) {
      final repo = _FakeRepo();
      final client = _FakeRealtimeClient();
      final c1 = Completer<MessagePage>(); // initial load
      repo.enqueue(c1.future);

      final container = _makeContainer(repo, client: client);

      // Prime connectCount to 1 BEFORE chatProvider is built so the reconnect
      // listener (registered in build()) doesn't see this first event.
      container.read(realtimeNotifierProvider); // initialise RealtimeNotifier
      client.emitState(RealtimeConnectionState.connected); // connectCount → 1
      async.flushMicrotasks();

      // Open the chat — initial load starts, seq=1, _initialLoadDone=false
      final notifier = container.read(chatProvider.notifier);
      container.listen(chatProvider, (_, _) {}); // keep autoDispose provider alive
      notifier.open(conversationId: 'conv1', summary: _summary());
      async.flushMicrotasks();

      // Simulate a reconnect: emits connected with connectCount=2, fires the
      // ref.listen callback inside ChatNotifier.build().
      client.emitState(RealtimeConnectionState.disconnected);
      async.flushMicrotasks();
      client.emitState(RealtimeConnectionState.connected); // connectCount → 2
      async.flushMicrotasks();
      // Debounce timer scheduled (3 s). Advance past it:
      async.elapse(const Duration(seconds: 4));
      // _reconnectRefetch fired but _initialLoadDone=false → exits early.
      // getMessages was called once (initial load only); refetch was blocked.
      expect(repo.getMessagesCallCount, 1,
          reason: 'reconnect refetch must not issue getMessages before '
              'the initial load completes (_initialLoadDone guard)');

      // Complete the initial load
      c1.complete(_page([_msg('m0')]));
      async.flushMicrotasks();

      expect(container.read(chatProvider).isLoading, isFalse,
          reason: 'initial load completion clears isLoading');

      // A second reconnect AFTER initial load SHOULD trigger a refetch
      client.emitState(RealtimeConnectionState.disconnected);
      async.flushMicrotasks();
      client.emitState(RealtimeConnectionState.connected); // connectCount → 3
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(repo.getMessagesCallCount, 2,
          reason: 'reconnect refetch works normally after initial load');

      // State must be consistent — no permanent spinner regardless of race
      expect(container.read(chatProvider).isLoading, isFalse);

      container.dispose();
    });
  });

  test('6. opening a chat with connectCount already high does NOT refetch', () {
    // Regression: connectCount is global and monotonic. The old condition
    // `connectCount > 1` was permanently true after the app's first reconnect
    // (observed count=6 on device), so EVERY chat open scheduled a reconnect
    // refetch racing the initial load. The baseline fix means a chat opened
    // while already connected must never trigger a refetch on open.
    fakeAsync((async) {
      final repo = _FakeRepo();
      final client = _FakeRealtimeClient();
      final c1 = Completer<MessagePage>();
      repo.enqueue(c1.future);

      final container = _makeContainer(repo, client: client);
      container.read(realtimeNotifierProvider);
      // Simulate 6 background/resume reconnect cycles BEFORE the chat opens.
      for (var i = 0; i < 6; i++) {
        client.emitState(RealtimeConnectionState.disconnected);
        async.flushMicrotasks();
        client.emitState(RealtimeConnectionState.connected);
        async.flushMicrotasks();
      }

      final notifier = container.read(chatProvider.notifier);
      container.listen(chatProvider, (_, _) {}); // keep autoDispose alive
      notifier.open(conversationId: 'conv1', summary: _summary());
      async.flushMicrotasks();

      c1.complete(_page([_msg('m1')]));
      async.flushMicrotasks();
      expect(container.read(chatProvider).isLoading, isFalse,
          reason: 'initial load must complete normally');

      // Long after open + past any debounce window: still exactly ONE fetch.
      // No reconnect happened after this screen opened (count == baseline == 6).
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(repo.getMessagesCallCount, 1,
          reason: 'a high absolute connectCount alone must never trigger '
              'a reconnect refetch — the trigger must be relative to this '
              "notifier's baseline");

      container.dispose();
    });
  });

  test('7. reconnect above the baseline after open DOES refetch', () {
    // Complement of test 6: with the same high starting count (6), a genuine
    // reconnect after the screen opened (count rises to 7 > baseline 6) must
    // still top up the gap — and must leave isLoading untouched.
    fakeAsync((async) {
      final repo = _FakeRepo();
      final client = _FakeRealtimeClient();
      final c1 = Completer<MessagePage>();
      repo.enqueue(c1.future);

      final container = _makeContainer(repo, client: client);
      container.read(realtimeNotifierProvider);
      for (var i = 0; i < 6; i++) {
        client.emitState(RealtimeConnectionState.disconnected);
        async.flushMicrotasks();
        client.emitState(RealtimeConnectionState.connected);
        async.flushMicrotasks();
      }

      final notifier = container.read(chatProvider.notifier);
      container.listen(chatProvider, (_, _) {}); // keep autoDispose alive
      notifier.open(conversationId: 'conv1', summary: _summary());
      async.flushMicrotasks();
      c1.complete(_page([_msg('m1')]));
      async.flushMicrotasks();
      expect(container.read(chatProvider).isLoading, isFalse);

      // Genuine reconnect AFTER open: count 6 → 7, above the baseline.
      client.emitState(RealtimeConnectionState.disconnected);
      async.flushMicrotasks();
      client.emitState(RealtimeConnectionState.connected); // count → 7
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 4)); // past the 3 s debounce
      async.flushMicrotasks();

      expect(repo.getMessagesCallCount, 2,
          reason: 'count above baseline = real gap = refetch must run');
      expect(container.read(chatProvider).isLoading, isFalse,
          reason: 'reconnect refetch is a background top-up — it must never '
              'touch isLoading');

      container.dispose();
    });
  });

  // ── M4: ConversationRead read-receipt watermark ────────────────────────────
  group('ConversationRead (M4 read receipts)', () {
    RealtimeEvent readEvent(String convId, DateTime lastReadAt) =>
        RealtimeEvent('ConversationRead', {
          'conversationId': convId,
          'lastReadAt': lastReadAt.toIso8601String(),
        });

    test('8. seeds otherLastReadAt from the summary on open', () async {
      final repo = _FakeRepo();
      repo.enqueue(Future.value(_page([_msg('m1')])));
      final container = _makeContainer(repo);
      container.listen(chatProvider, (_, _) {});
      addTearDown(container.dispose);

      final watermark = DateTime.utc(2026, 8, 31, 12);
      container.read(chatProvider.notifier).open(
            conversationId: 'conv1',
            summary: _summary(otherLastReadAt: watermark),
          );
      await Future<void>.delayed(Duration.zero);

      expect(container.read(chatProvider).otherLastReadAt, watermark,
          reason: 'hot-open seeds the watermark from the summary');
    });

    test('9. event for the open conversation advances the watermark', () async {
      final repo = _FakeRepo();
      repo.enqueue(Future.value(_page([_msg('m1')])));
      final client = _FakeRealtimeClient();
      final container = _makeContainer(repo, client: client);
      container.listen(chatProvider, (_, _) {});
      addTearDown(container.dispose);

      container.read(chatProvider.notifier).open(
          conversationId: 'conv1', summary: _summary());
      await Future<void>.delayed(Duration.zero);
      expect(container.read(chatProvider).otherLastReadAt, isNull);

      final ts = DateTime.utc(2026, 8, 31, 12);
      client.emitEvent(readEvent('conv1', ts));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(chatProvider).otherLastReadAt, ts,
          reason: 'event for the open chat advances the watermark');
    });

    test('10. event for a DIFFERENT conversation is ignored', () async {
      final repo = _FakeRepo();
      repo.enqueue(Future.value(_page([_msg('m1')])));
      final client = _FakeRealtimeClient();
      final container = _makeContainer(repo, client: client);
      container.listen(chatProvider, (_, _) {});
      addTearDown(container.dispose);

      container.read(chatProvider.notifier).open(
          conversationId: 'conv1', summary: _summary());
      await Future<void>.delayed(Duration.zero);

      client.emitEvent(readEvent('other-conv', DateTime.utc(2026, 8, 31, 12)));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(chatProvider).otherLastReadAt, isNull,
          reason: 'a read on another conversation must not touch this one');
    });

    test('11. out-of-order (older) event never moves the watermark backwards',
        () async {
      final repo = _FakeRepo();
      repo.enqueue(Future.value(_page([_msg('m1')])));
      final client = _FakeRealtimeClient();
      final container = _makeContainer(repo, client: client);
      container.listen(chatProvider, (_, _) {});
      addTearDown(container.dispose);

      final newer = DateTime.utc(2026, 8, 31, 12);
      container.read(chatProvider.notifier).open(
            conversationId: 'conv1',
            summary: _summary(otherLastReadAt: newer),
          );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(chatProvider).otherLastReadAt, newer);

      // A stale event carrying an OLDER timestamp arrives late.
      client.emitEvent(readEvent('conv1', DateTime.utc(2026, 8, 31, 11)));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(chatProvider).otherLastReadAt, newer,
          reason: 'a tick must never flip read → sent on a reordered event');
    });
  });

  // ── F-M7: reactions (optimistic + event merge) ─────────────────────────────
  group('reactions', () {
    test('12. reacting adds optimistically then reconciles the server aggregate',
        () async {
      final repo = _FakeRepo();
      repo.enqueue(Future.value(_page([_msg('m1')])));
      final container = _makeContainer(repo);
      container.listen(chatProvider, (_, _) {});
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      notifier.open(conversationId: 'conv1', summary: _summary());
      await Future<void>.delayed(Duration.zero);

      final err = await notifier.toggleReaction('m1', '👍');
      expect(err, isNull);
      final msg =
          container.read(chatProvider).messages.firstWhere((m) => m.id == 'm1');
      expect(msg.myReactionEmoji, '👍');
      final b = msg.reactions.firstWhere((r) => r.emoji == '👍');
      expect(b.count, 1);
      expect(b.reactedByMe, isTrue);
      expect(repo.reactCallCount, 1);
    });

    test('13. a failed reaction rolls back to the previous state and returns an error',
        () async {
      final repo = _FakeRepo()..reactShouldFail = true;
      repo.enqueue(Future.value(_page([_msg('m1')])));
      final container = _makeContainer(repo);
      container.listen(chatProvider, (_, _) {});
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      notifier.open(conversationId: 'conv1', summary: _summary());
      await Future<void>.delayed(Duration.zero);

      final err = await notifier.toggleReaction('m1', '👍');
      expect(err, isNotNull, reason: 'failure surfaces a user-facing message');
      final msg =
          container.read(chatProvider).messages.firstWhere((m) => m.id == 'm1');
      expect(msg.myReactionEmoji, isNull, reason: 'rolled back');
      expect(msg.reactions, isEmpty,
          reason: 'the optimistic bucket is removed on rollback');
    });

    test('14. a second tap while a call is in flight is dropped (one call only)',
        () async {
      final repo = _FakeRepo()..reactGate = Completer<List<MessageReaction>>();
      repo.enqueue(Future.value(_page([_msg('m1')])));
      final container = _makeContainer(repo);
      container.listen(chatProvider, (_, _) {});
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      notifier.open(conversationId: 'conv1', summary: _summary());
      await Future<void>.delayed(Duration.zero);

      final f1 = notifier.toggleReaction('m1', '👍'); // gated, in flight
      await Future<void>.delayed(Duration.zero);
      final second = await notifier.toggleReaction('m1', '❤️'); // dropped
      expect(second, isNull);
      expect(repo.reactCallCount, 1,
          reason: 'a double-tap must not spawn a second in-flight call');

      repo.reactGate!
          .complete([MessageReaction(emoji: '👍', count: 1, reactedByMe: true)]);
      await f1;
    });

    test('15. ReactionChanged merges counts but preserves the caller reactedByMe',
        () async {
      final repo = _FakeRepo();
      repo.enqueue(Future.value(_page([_msg('m1')])));
      final client = _FakeRealtimeClient();
      final container = _makeContainer(repo, client: client);
      container.listen(chatProvider, (_, _) {});
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      notifier.open(conversationId: 'conv1', summary: _summary());
      await Future<void>.delayed(Duration.zero);

      await notifier.toggleReaction('m1', '👍'); // caller now owns 👍

      // Event: 👍 climbs to 2 (someone else), reactedByMe STRIPPED to false.
      client.emitEvent(RealtimeEvent('ReactionChanged', {
        'conversationId': 'conv1',
        'messageId': 'm1',
        'reactions': [
          {'emoji': '👍', 'count': 2, 'reactedByMe': false},
        ],
      }));
      await Future<void>.delayed(Duration.zero);

      final msg =
          container.read(chatProvider).messages.firstWhere((m) => m.id == 'm1');
      final b = msg.reactions.firstWhere((r) => r.emoji == '👍');
      expect(b.count, 2, reason: 'server count is authoritative');
      expect(b.reactedByMe, isTrue,
          reason: 're-derived from myReactionEmoji, never from the stripped event');
    });

    test('16. ReactionChanged for a message not in local state is ignored',
        () async {
      final repo = _FakeRepo();
      repo.enqueue(Future.value(_page([_msg('m1')])));
      final client = _FakeRealtimeClient();
      final container = _makeContainer(repo, client: client);
      container.listen(chatProvider, (_, _) {});
      addTearDown(container.dispose);
      final notifier = container.read(chatProvider.notifier);
      notifier.open(conversationId: 'conv1', summary: _summary());
      await Future<void>.delayed(Duration.zero);

      client.emitEvent(RealtimeEvent('ReactionChanged', {
        'conversationId': 'conv1',
        'messageId': 'ghost',
        'reactions': [
          {'emoji': '👍', 'count': 1, 'reactedByMe': false},
        ],
      }));
      await Future<void>.delayed(Duration.zero);

      final msg =
          container.read(chatProvider).messages.firstWhere((m) => m.id == 'm1');
      expect(msg.reactions, isEmpty,
          reason: 'an event for another message must not touch this one');
    });
  });
}
