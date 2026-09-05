// ChatScreen WIDGET test — regression for the build-phase mutation bug.
//
// The notifier unit tests (chat_notifier_test.dart) call open() directly and
// so can never catch "Tried to modify a provider while the widget tree was
// building" — that throw only exists inside the widget lifecycle. This test
// pumps the real screen: under the old code (open() called synchronously in
// initState), pumpWidget captures the Riverpod assertion as a test exception
// and the spinner never clears. Under the fixed code (open() deferred via
// addPostFrameCallback), no exception is thrown and the message renders.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:freelancer_frontend/core/models/paged_result.dart';
import 'package:freelancer_frontend/core/realtime/realtime_client.dart';
import 'package:freelancer_frontend/core/realtime/realtime_notifier.dart';
import 'package:freelancer_frontend/features/messaging/data/messaging_repository.dart';
import 'package:freelancer_frontend/features/messaging/data/models/messaging_models.dart';
import 'package:freelancer_frontend/features/messaging/presentation/screens/chat_screen.dart';

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
}

class _FakeRepo implements MessagingRepository {
  @override
  Future<MessagePage> getMessages(String conversationId,
          {DateTime? before, int limit = 30}) async =>
      MessagePage(
        items: [
          Message(
            id: 'm1',
            conversationId: 'conv1',
            senderId: 'u2',
            body: 'hello from the other side',
            type: MessageType.text,
            createdAt: DateTime.utc(2025, 1, 1),
          ),
        ],
        hasMore: false,
      );

  @override
  Future<void> markRead(String conversationId) async {}

  @override
  Future<void> markPlayed(String conversationId, String messageId) async {}

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

  // ── M2 message actions (unused by this test) ──────────────────────────────
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
  Future<List<MessageReaction>> reactToMessage(String c, String m, String e) async => [];
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
}

ConversationSummary _summary() => const ConversationSummary(
      id: 'conv1',
      status: ConversationStatus.accepted,
      isRequest: false,
      otherUser: ConversationUser(userId: 'u2', fullName: 'Test User'),
      unreadCount: 0, // 0 → no markRead debounce timer in the test
    );

void main() {
  testWidgets(
      'ChatScreen: no build-phase provider mutation; spinner clears and '
      'messages render', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          realtimeClientProvider.overrideWithValue(_FakeRealtimeClient()),
          messagingRepositoryProvider.overrideWithValue(_FakeRepo()),
        ],
        child: MaterialApp(
          home: ChatScreen(conversationId: 'conv1', summary: _summary()),
        ),
      ),
    );

    // THE regression assertion: under the old code, open() ran synchronously
    // in initState and Riverpod threw "Tried to modify a provider while the
    // widget tree was building" during this first pump.
    expect(tester.takeException(), isNull,
        reason: 'initState must not mutate providers during build');

    // First frame: open() has not run yet (deferred) — spinner is correct.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Next frames: post-frame callback fires open(), fake repo resolves.
    await tester.pump(); // run the post-frame callback
    await tester.pump(); // flush the getMessages microtask → state update

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'spinner must dismiss once the load completes');
    expect(find.text('hello from the other side'), findsOneWidget);

    // Navigate away: dispose must also not mutate providers synchronously.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'dispose must not mutate providers during teardown');
  });
}
