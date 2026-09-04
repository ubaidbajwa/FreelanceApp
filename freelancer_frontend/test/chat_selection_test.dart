// ChatNotifier selection-mode + copy/delete/pin + M2 realtime tests.
//
// Exercises the notifier directly (no widget tree) so the selection/deletion
// state machine is verified where the bugs would be silent: wrong scope applied,
// tombstone not rendered, partial-failure discarded, realtime event dropped.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:freelancer_frontend/core/models/paged_result.dart';
import 'package:freelancer_frontend/core/realtime/realtime_client.dart';
import 'package:freelancer_frontend/core/realtime/realtime_notifier.dart';
import 'package:freelancer_frontend/features/messaging/application/chat_notifier.dart';
import 'package:freelancer_frontend/features/messaging/data/messaging_repository.dart';
import 'package:freelancer_frontend/features/messaging/data/models/messaging_models.dart';

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

  void emitEvent(RealtimeEvent e) => _eventsCtrl.add(e);
}

class _FakeRepo implements MessagingRepository {
  _FakeRepo(this._page);
  final MessagePage _page;

  final deleteCalls = <(String, String)>[]; // (messageId, scope)
  final pinCalls = <String>[];
  final pinDurations = <PinDuration>[]; // duration per pin call
  final pinReplaceFlags = <bool>[]; // replaceOldest per pin call
  final unpinCalls = <String>[];

  Set<String> failDeleteIds = {};
  Object? pinError;

  @override
  Future<MessagePage> getMessages(String conversationId,
          {DateTime? before, int limit = 30}) async =>
      _page;

  @override
  Future<void> deleteMessage(String conversationId, String messageId,
      {required String scope}) async {
    deleteCalls.add((messageId, scope));
    if (failDeleteIds.contains(messageId)) {
      throw DioException(requestOptions: RequestOptions(path: ''));
    }
  }

  @override
  Future<void> pinMessage(
    String conversationId,
    String messageId, {
    required PinDuration duration,
    bool replaceOldest = false,
  }) async {
    if (pinError != null) throw pinError!;
    pinCalls.add(messageId);
    pinDurations.add(duration);
    pinReplaceFlags.add(replaceOldest);
  }

  @override
  Future<void> unpinMessage(String conversationId, String messageId) async {
    if (pinError != null) throw pinError!;
    unpinCalls.add(messageId);
  }

  @override
  Future<void> markRead(String conversationId) async {}

  // ---- unused in these tests ----
  @override
  Future<List<Message>> getPinnedMessages(String conversationId) async => [];
  @override
  Future<List<MessageReaction>> reactToMessage(
          String c, String m, String e) async =>
      [];
  @override
  Future<void> removeReaction(String c, String m) async {}
  @override
  Future<Message> editMessage(String c, String m, String b) =>
      Future.error(UnimplementedError());
  @override
  Future<List<Message>> forwardMessages(String c,
          {required String targetConversationId,
          required List<String> messageIds}) async =>
      [];
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
  Future<ConversationSummary> startOrGetConversation(String r) =>
      Future.error(UnimplementedError());
  @override
  Future<Message> sendMessage(String c, String b,
          {String? replyToMessageId}) =>
      Future.error(UnimplementedError());
  @override
  Future<Message> sendMediaMessage(String c, String filePath,
          {String? caption,
          String? replyToMessageId,
          String? waveform,
          void Function(int, int)? onSendProgress,
          CancelToken? cancelToken}) =>
      Future.error(UnimplementedError());
  @override
  Future<void> acceptConversation(String c) async {}
  @override
  Future<void> declineConversation(String c) async {}
  @override
  Future<ConversationSummary> getConversation(String c) =>
      Future.error(UnimplementedError());
}

ConversationSummary _summary() => const ConversationSummary(
      id: 'conv1',
      status: ConversationStatus.accepted,
      isRequest: false,
      otherUser: ConversationUser(userId: 'u2', fullName: 'Other'),
      unreadCount: 0,
    );

// senderId 'u1' → mine (other is u2); 'u2' → other.
Message _msg(String id, {String sender = 'u1', bool isPinned = false}) => Message(
      id: id,
      conversationId: 'conv1',
      senderId: sender,
      body: 'body-$id',
      type: MessageType.text,
      createdAt: DateTime.utc(2026, 1, 1),
      isPinned: isPinned,
    );

Future<ChatNotifier> _open(ProviderContainer c) async {
  final n = c.read(chatProvider.notifier);
  c.listen(chatProvider, (_, _) {});
  await n.open(conversationId: 'conv1', summary: _summary());
  await Future<void>.delayed(Duration.zero);
  return n;
}

ProviderContainer _container(_FakeRepo repo, _FakeRealtimeClient client) =>
    ProviderContainer(overrides: [
      realtimeClientProvider.overrideWithValue(client),
      messagingRepositoryProvider.overrideWithValue(repo),
    ]);

void main() {
  MessagePage page(List<Message> m) => MessagePage(items: m, hasMore: false);

  test('long-press enters selection; tap toggles; zero exits', () async {
    final repo = _FakeRepo(page([_msg('m1'), _msg('m2', sender: 'u2')]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('m1');
    expect(c.read(chatProvider).isSelecting, isTrue);
    expect(c.read(chatProvider).selectedMessageIds, {'m1'});

    n.toggleSelection('m2');
    expect(c.read(chatProvider).selectedMessageIds, {'m1', 'm2'});

    n.toggleSelection('m1');
    n.toggleSelection('m2');
    expect(c.read(chatProvider).isSelecting, isFalse,
        reason: 'selecting down to zero exits selection mode');
  });

  test('tombstone is not selectable', () async {
    final repo = _FakeRepo(page([_msg('m1')]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    // Turn m1 into a tombstone via a delete-for-everyone realtime event.
    client.emitEvent(const RealtimeEvent(
        'MessageDeleted', {'conversationId': 'conv1', 'messageId': 'm1'}));
    await Future<void>.delayed(Duration.zero);

    n.enterSelection('m1');
    expect(c.read(chatProvider).isSelecting, isFalse);
  });

  test('delete for me removes the rows and exits selection', () async {
    final repo = _FakeRepo(page([_msg('m1'), _msg('m2')]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('m1');
    final outcome = await n.deleteSelected(scope: 'me');

    expect(repo.deleteCalls, [('m1', 'me')]);
    expect(outcome.succeeded, 1);
    expect(outcome.failed, 0);
    final ids = c.read(chatProvider).messages.map((m) => m.id).toList();
    expect(ids, ['m2'], reason: 'deleted-for-me row is gone entirely');
    expect(c.read(chatProvider).isSelecting, isFalse);
  });

  test('delete for everyone tombstones in place (row stays, body blank)',
      () async {
    final repo = _FakeRepo(page([_msg('m1'), _msg('m2')]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('m1');
    await n.deleteSelected(scope: 'everyone');

    expect(repo.deleteCalls, [('m1', 'everyone')]);
    final m1 = c.read(chatProvider).messages.firstWhere((m) => m.id == 'm1');
    expect(m1.isDeleted, isTrue);
    expect(m1.body, isEmpty);
    expect(c.read(chatProvider).messages, hasLength(2),
        reason: 'tombstone remains in place, not removed');
  });

  test('delete partial failure removes only successes and reports failures',
      () async {
    final repo = _FakeRepo(page([_msg('m1'), _msg('m2')]))
      ..failDeleteIds = {'m2'};
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('m1');
    n.toggleSelection('m2');
    final outcome = await n.deleteSelected(scope: 'me');

    expect(outcome.succeeded, 1);
    expect(outcome.failed, 1);
    expect(outcome.firstError, isNotNull);
    final ids = c.read(chatProvider).messages.map((m) => m.id).toList();
    expect(ids, ['m2'], reason: 'only the successfully-deleted row is removed');
  });

  test('pin single selection sends the chosen duration and exits selection',
      () async {
    final repo = _FakeRepo(page([_msg('m1')]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('m1');
    final outcome = await n.pinSelected(duration: PinDuration.sevenDays);

    expect(outcome.kind, PinOutcomeKind.success);
    expect(repo.pinCalls, ['m1']);
    expect(repo.pinDurations, [PinDuration.sevenDays]);
    expect(repo.pinReplaceFlags, [false]);
    expect(c.read(chatProvider).messages.first.isPinned, isTrue);
    expect(c.read(chatProvider).isSelecting, isFalse);
  });

  test('unpinSelected unpins an already-pinned message', () async {
    final repo = _FakeRepo(page([_msg('m1', isPinned: true)]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('m1');
    final err = await n.unpinSelected();

    expect(err, isNull);
    expect(repo.unpinCalls, ['m1']);
    expect(c.read(chatProvider).messages.first.isPinned, isFalse);
  });

  test('pin cap (409) returns capReached and keeps the selection', () async {
    final repo = _FakeRepo(page([_msg('m1')]))
      ..pinError = DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
            requestOptions: RequestOptions(path: ''), statusCode: 409),
      );
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('m1');
    final outcome = await n.pinSelected(duration: PinDuration.twentyFourHours);

    expect(outcome.kind, PinOutcomeKind.capReached,
        reason: '409 must be a distinct outcome the screen can branch on');
    expect(c.read(chatProvider).isSelecting, isTrue,
        reason: 'cap-reached keeps the selection so the retry targets it');
  });

  test('replace retry re-pins with replaceOldest and the same duration',
      () async {
    // First call 409s (cap); after clearing the error the retry succeeds.
    final repo = _FakeRepo(page([_msg('m1')]))
      ..pinError = DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
            requestOptions: RequestOptions(path: ''), statusCode: 409),
      );
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('m1');
    final first = await n.pinSelected(duration: PinDuration.thirtyDays);
    expect(first.kind, PinOutcomeKind.capReached);

    repo.pinError = null; // user tapped Continue
    final retry = await n.pinSelected(
        duration: PinDuration.thirtyDays, replaceOldest: true);

    expect(retry.kind, PinOutcomeKind.success);
    expect(repo.pinReplaceFlags.last, isTrue);
    expect(repo.pinDurations.last, PinDuration.thirtyDays,
        reason: 'the chosen duration must survive the replace retry');
  });

  test('system message is inert — not selectable', () async {
    final sys = Message(
      id: 's1',
      conversationId: 'conv1',
      senderId: 'u2',
      body: '',
      type: MessageType.system,
      createdAt: DateTime.utc(2026, 1, 1),
      systemEventType: SystemEventType.messagePinned,
    );
    final repo = _FakeRepo(page([sys, _msg('m1')]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('s1');
    expect(c.read(chatProvider).isSelecting, isFalse,
        reason: 'system notices cannot enter selection');
    n.enterSelection('m1');
    n.toggleSelection('s1');
    expect(c.read(chatProvider).selectedMessageIds, {'m1'},
        reason: 'toggling a system notice while selecting is a no-op');
  });

  test('realtime MessagePinChanged updates isPinned and carries pinExpiresAt',
      () async {
    final repo = _FakeRepo(page([_msg('m1')]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    await _open(c);

    client.emitEvent(const RealtimeEvent('MessagePinChanged', {
      'conversationId': 'conv1',
      'messageId': 'm1',
      'isPinned': true,
      'pinExpiresAt': '2026-02-01T10:00:00Z',
    }));
    await Future<void>.delayed(Duration.zero);

    final m = c.read(chatProvider).messages.first;
    expect(m.isPinned, isTrue);
    expect(m.pinExpiresAt, DateTime.utc(2026, 2, 1, 10));
  });

  test('MessagePinChanged clamps the index when the shown pin is removed',
      () async {
    final repo = _FakeRepo(page([_msg('m1'), _msg('m2')]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    // Pin two, advance the banner to the second (index 1), then unpin it.
    client.emitEvent(const RealtimeEvent('MessagePinChanged',
        {'conversationId': 'conv1', 'messageId': 'm1', 'isPinned': true}));
    client.emitEvent(const RealtimeEvent('MessagePinChanged',
        {'conversationId': 'conv1', 'messageId': 'm2', 'isPinned': true}));
    await Future<void>.delayed(Duration.zero);
    n.cyclePin(); // index → 1
    client.emitEvent(const RealtimeEvent('MessagePinChanged',
        {'conversationId': 'conv1', 'messageId': 'm2', 'isPinned': false}));
    await Future<void>.delayed(Duration.zero);

    final st = c.read(chatProvider);
    expect(st.pinnedMessages, hasLength(1));
    expect(st.pinnedIndex, 0, reason: 'index clamps into range, never crashes');
  });

  test('buildCopyText joins selected bodies in chronological order', () async {
    // Newest-first list: [m2 (newer), m1 (older)] — copy must be oldest-first.
    final older = Message(
        id: 'm1',
        conversationId: 'conv1',
        senderId: 'u1',
        body: 'first',
        type: MessageType.text,
        createdAt: DateTime.utc(2026, 1, 1, 10));
    final newer = Message(
        id: 'm2',
        conversationId: 'conv1',
        senderId: 'u1',
        body: 'second',
        type: MessageType.text,
        createdAt: DateTime.utc(2026, 1, 1, 11));
    final repo = _FakeRepo(page([newer, older]));
    final client = _FakeRealtimeClient();
    final c = _container(repo, client);
    addTearDown(c.dispose);
    final n = await _open(c);

    n.enterSelection('m1');
    n.toggleSelection('m2');
    expect(n.buildCopyText(), 'first\nsecond');
  });
}
