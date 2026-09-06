// ChatScreen selection-mode WIDGET test — verifies the wiring the notifier tests
// can't see: long-press swaps in the selection app bar (count via formatCount +
// action icons), the back arrow exits selection, and the delete dialog offers the
// right options for an OWN, recent message (both "for everyone" and "for me").

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
import 'package:freelancer_frontend/features/messaging/messaging_strings.dart';
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
            senderId: 'u1', // mine (other is u2)
            body: 'my recent message',
            type: MessageType.text,
            createdAt: DateTime.now().toUtc(), // within 48h window
          ),
        ],
        hasMore: false,
      );

  @override
  Future<void> markRead(String c) async {}
  @override
  Future<void> markPlayed(String c, String m) async {}
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
  @override
  Future<PagedResult<ConversationSummary>> getConversations(
          {int page = 1, int pageSize = 20}) async =>
      const PagedResult(
          items: [], page: 1, pageSize: 20, totalCount: 0, totalPages: 0, hasNextPage: false);
  @override
  Future<PagedResult<ConversationSummary>> getRequests(
          {int page = 1, int pageSize = 20}) async =>
      const PagedResult(
          items: [], page: 1, pageSize: 20, totalCount: 0, totalPages: 0, hasNextPage: false);
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
          String? fileName,
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
      otherUser: ConversationUser(userId: 'u2', fullName: 'Other User'),
      unreadCount: 0,
    );

void main() {
  testWidgets('long-press enters selection; back exits; delete dialog shows '
      'own-message options', (tester) async {
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
    await tester.pump(); // post-frame open()
    await tester.pump(); // getMessages resolves

    expect(find.text('my recent message'), findsOneWidget);
    // Normal app bar shows the other user's name.
    expect(find.text('Other User'), findsOneWidget);

    // Long-press enters selection mode.
    await tester.longPress(find.text('my recent message'));
    await tester.pumpAndSettle();

    // Selection app bar: count via formatCount ('1') + action icons.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Other User'), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

    // Tap delete → dialog offers both options for an own, recent message.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text(MessagingStrings.deleteForEveryone), findsOneWidget);
    expect(find.text(MessagingStrings.deleteForMe), findsOneWidget);
    expect(find.text(MessagingStrings.cancel), findsOneWidget);

    // Dismiss the dialog (Cancel) then exit selection via the back arrow.
    await tester.tap(find.text(MessagingStrings.cancel));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    // Back in the normal app bar; no selection count.
    expect(find.text('Other User'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
  });
}
