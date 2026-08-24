// Message.fromJson parsing tests for the M2 message-action fields.
//
// The M2 backend added replyTo / reactions / editedAt / isPinned /
// pinnedByUserId / isForwarded to MessageDto. Parsing must be ADDITIVE — an old
// payload (or a text message with none of these) still parses, defaulting every
// new field. A message from another client could already carry replyTo before
// the reply UI ships, so we parse it now rather than silently dropping it.

import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer_frontend/features/messaging/data/models/messaging_models.dart';

void main() {
  group('Message.fromJson — additive M2 fields', () {
    test('minimal payload defaults every new field (nothing dropped, no throw)',
        () {
      final m = Message.fromJson(<String, dynamic>{
        'id': 'm1',
        'conversationId': 'c1',
        'senderId': 'u1',
        'body': 'hello',
        'type': 0,
        'createdAt': '2026-01-01T10:00:00Z',
      });

      expect(m.replyTo, isNull);
      expect(m.reactions, isEmpty);
      expect(m.editedAt, isNull);
      expect(m.isPinned, isFalse);
      expect(m.pinnedByUserId, isNull);
      expect(m.isForwarded, isFalse);
    });

    test('full payload parses every new field with camelCase keys', () {
      final m = Message.fromJson(<String, dynamic>{
        'id': 'm2',
        'conversationId': 'c1',
        'senderId': 'u1',
        'body': 'edited body',
        'type': 0,
        'createdAt': '2026-01-01T10:00:00Z',
        'isDeleted': false,
        'editedAt': '2026-01-01T10:05:00Z',
        'isPinned': true,
        'pinnedByUserId': 'u2',
        'isForwarded': true,
        'replyTo': <String, dynamic>{
          'messageId': 'm0',
          'senderId': 'u2',
          'senderName': 'Ada',
          'bodySnippet': 'the quoted text',
          'type': 0,
          'isDeleted': false,
        },
        'reactions': <dynamic>[
          <String, dynamic>{'emoji': '👍', 'count': 2, 'reactedByMe': true},
          <String, dynamic>{'emoji': '❤️', 'count': 1, 'reactedByMe': false},
        ],
      });

      expect(m.editedAt, DateTime.utc(2026, 1, 1, 10, 5));
      expect(m.isPinned, isTrue);
      expect(m.pinnedByUserId, 'u2');
      expect(m.isForwarded, isTrue);

      final reply = m.replyTo;
      expect(reply, isNotNull);
      expect(reply!.messageId, 'm0');
      expect(reply.senderId, 'u2');
      expect(reply.senderName, 'Ada');
      expect(reply.bodySnippet, 'the quoted text');
      expect(reply.type, MessageType.text);
      expect(reply.isDeleted, isFalse);

      expect(m.reactions, hasLength(2));
      expect(m.reactions.first.emoji, '👍');
      expect(m.reactions.first.count, 2);
      expect(m.reactions.first.reactedByMe, isTrue);
      expect(m.reactions[1].reactedByMe, isFalse);
    });

    test('replyTo to a deleted message parses the tombstone flag', () {
      final m = Message.fromJson(<String, dynamic>{
        'id': 'm3',
        'conversationId': 'c1',
        'senderId': 'u1',
        'body': 'reply to deleted',
        'type': 0,
        'createdAt': '2026-01-01T10:00:00Z',
        'replyTo': <String, dynamic>{
          'messageId': 'm0',
          'senderId': 'u2',
          'senderName': 'Ada',
          'bodySnippet': '',
          'type': 0,
          'isDeleted': true,
        },
      });

      expect(m.replyTo!.isDeleted, isTrue);
      expect(m.replyTo!.bodySnippet, isEmpty);
    });
  });

  group('M3 — MessageType.system + system/pin fields', () {
    test('MessageType.fromApi(4) is system; unknown falls back to text', () {
      expect(MessageType.fromApi(4), MessageType.system);
      expect(MessageType.fromApi(99), MessageType.text);
    });

    test('SystemEventType.fromApi maps 0/1 and defaults null', () {
      expect(SystemEventType.fromApi(0), SystemEventType.messagePinned);
      expect(SystemEventType.fromApi(1), SystemEventType.messageUnpinned);
      expect(SystemEventType.fromApi(null), isNull);
      expect(SystemEventType.fromApi(7), isNull);
    });

    test('PinDuration.apiValue matches the wire ints', () {
      expect(PinDuration.twentyFourHours.apiValue, 0);
      expect(PinDuration.sevenDays.apiValue, 1);
      expect(PinDuration.thirtyDays.apiValue, 2);
    });

    test('legacy pin (no pinExpiresAt) parses as null — never assume permanent',
        () {
      final m = Message.fromJson(<String, dynamic>{
        'id': 'm1',
        'conversationId': 'c1',
        'senderId': 'u1',
        'body': 'hi',
        'type': 0,
        'createdAt': '2026-01-01T10:00:00Z',
        'isPinned': true,
      });
      expect(m.pinExpiresAt, isNull);
      expect(m.systemEventType, isNull);
      expect(m.systemTargetMessageId, isNull);
    });

    test('system message payload parses type/eventType/target/expiry', () {
      final m = Message.fromJson(<String, dynamic>{
        'id': 's1',
        'conversationId': 'c1',
        'senderId': 'u2',
        'body': '',
        'type': 4,
        'createdAt': '2026-01-01T10:00:00Z',
        'systemEventType': 0,
        'systemTargetMessageId': 'm9',
        'pinExpiresAt': '2026-01-08T10:00:00Z',
      });

      expect(m.type, MessageType.system);
      expect(m.body, isEmpty);
      expect(m.systemEventType, SystemEventType.messagePinned);
      expect(m.systemTargetMessageId, 'm9');
      expect(m.pinExpiresAt, DateTime.utc(2026, 1, 8, 10));
    });
  });
}
