// The two explicit, testable decision functions at the core of this slice:
//   resolveToolbarActions  — which toolbar icons show for a given selection
//   resolveDeleteOptions   — which delete-dialog options apply (ownership + 48h)
//
// Keeping the conditional logic in pure functions (rather than scattered ifs in
// the widget tree) is the whole point — every row of the spec's action table is
// a test here.

import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer_frontend/features/messaging/application/chat_notifier.dart';
import 'package:freelancer_frontend/features/messaging/application/message_actions.dart';
import 'package:freelancer_frontend/features/messaging/data/models/messaging_models.dart';
import 'package:freelancer_frontend/features/messaging/messaging_strings.dart';

ChatMessage _m({
  String id = 'm',
  bool isMine = true,
  MessageType type = MessageType.text,
  bool isDeleted = false,
  bool isPinned = false,
  DateTime? createdAt,
}) =>
    ChatMessage(
      id: id,
      senderId: isMine ? '' : 'other',
      body: 'body',
      type: type,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      status: ChatSendStatus.confirmed,
      isMine: isMine,
      isDeleted: isDeleted,
      isPinned: isPinned,
    );

void main() {
  group('resolveToolbarActions', () {
    test('single own text → copy, pin, delete (pin not unpin)', () {
      final a = resolveToolbarActions([_m(id: '1', isMine: true)]);
      expect(a.showCopy, isTrue);
      expect(a.showPin, isTrue);
      expect(a.showDelete, isTrue);
      expect(a.isUnpin, isFalse);
    });

    test("single other's text → copy, pin, delete", () {
      final a = resolveToolbarActions([_m(id: '1', isMine: false)]);
      expect(a.showCopy, isTrue);
      expect(a.showPin, isTrue);
      expect(a.showDelete, isTrue);
    });

    test('multiple → copy + delete, NO pin', () {
      final a = resolveToolbarActions([_m(id: '1'), _m(id: '2')]);
      expect(a.showCopy, isTrue);
      expect(a.showDelete, isTrue);
      expect(a.showPin, isFalse);
    });

    test('mixed own + other → copy + delete, NO pin', () {
      final a = resolveToolbarActions([
        _m(id: '1', isMine: true),
        _m(id: '2', isMine: false),
      ]);
      expect(a.showCopy, isTrue);
      expect(a.showDelete, isTrue);
      expect(a.showPin, isFalse);
    });

    test('any non-text selected → copy hidden', () {
      final a = resolveToolbarActions([
        _m(id: '1', type: MessageType.text),
        _m(id: '2', type: MessageType.image),
      ]);
      expect(a.showCopy, isFalse);
      expect(a.showDelete, isTrue);
    });

    test('tombstone selected → copy hidden (no text to copy)', () {
      final a = resolveToolbarActions([_m(id: '1', isDeleted: true)]);
      expect(a.showCopy, isFalse);
    });

    test('single already-pinned → pin button becomes unpin', () {
      final a = resolveToolbarActions([_m(id: '1', isPinned: true)]);
      expect(a.showPin, isTrue);
      expect(a.isUnpin, isTrue);
    });

    test('empty selection → nothing shows', () {
      final a = resolveToolbarActions([]);
      expect(a.showCopy, isFalse);
      expect(a.showPin, isFalse);
      expect(a.showDelete, isFalse);
    });

    // F-M5: showReply
    test('single non-deleted → showReply true', () {
      final a = resolveToolbarActions([_m(id: '1')]);
      expect(a.showReply, isTrue);
    });

    test('multiple selection → showReply false', () {
      final a = resolveToolbarActions([_m(id: '1'), _m(id: '2')]);
      expect(a.showReply, isFalse);
    });

    test('single deleted → showReply false (tombstone guard)', () {
      final a = resolveToolbarActions([_m(id: '1', isDeleted: true)]);
      expect(a.showReply, isFalse);
    });
  });

  group('resolveDeleteOptions', () {
    final now = DateTime.utc(2026, 1, 2, 12); // fixed "now"

    test('own-only, recent → delete-for-everyone AND delete-for-me', () {
      final o = resolveDeleteOptions(
        [_m(id: '1', isMine: true, createdAt: now.subtract(const Duration(hours: 1)))],
        now: now,
      );
      expect(o.showDeleteForEveryone, isTrue);
      expect(o.showDeleteForMe, isTrue);
      expect(o.count, 1);
    });

    test("selection with other's message → delete-for-me only", () {
      final o = resolveDeleteOptions([
        _m(id: '1', isMine: false, createdAt: now),
      ], now: now);
      expect(o.showDeleteForEveryone, isFalse);
      expect(o.showDeleteForMe, isTrue);
    });

    test('mixed own + other → no delete-for-everyone', () {
      final o = resolveDeleteOptions([
        _m(id: '1', isMine: true, createdAt: now),
        _m(id: '2', isMine: false, createdAt: now),
      ], now: now);
      expect(o.showDeleteForEveryone, isFalse);
    });

    test('own but one older than 48h → delete-for-everyone hidden', () {
      final o = resolveDeleteOptions([
        _m(id: '1', isMine: true, createdAt: now.subtract(const Duration(hours: 1))),
        _m(id: '2', isMine: true, createdAt: now.subtract(const Duration(hours: 49))),
      ], now: now);
      expect(o.showDeleteForEveryone, isFalse);
      expect(o.showDeleteForMe, isTrue);
      expect(o.count, 2);
    });

    test('own exactly at the 48h boundary is still allowed', () {
      final o = resolveDeleteOptions([
        _m(id: '1', isMine: true, createdAt: now.subtract(const Duration(hours: 48))),
      ], now: now);
      expect(o.showDeleteForEveryone, isTrue);
    });
  });

  // ── F-M6: showForward ────────────────────────────────────────────────────────

  group('resolveToolbarActions – showForward', () {
    test('non-empty selection → showForward true', () {
      final a = resolveToolbarActions([_m(id: '1')]);
      expect(a.showForward, isTrue);
    });

    test('multiple selection → showForward true', () {
      final a = resolveToolbarActions([_m(id: '1'), _m(id: '2')]);
      expect(a.showForward, isTrue);
    });

    test('empty selection → showForward false', () {
      final a = resolveToolbarActions([]);
      expect(a.showForward, isFalse);
    });

    test('deleted message selected → showForward still true (forward guards elsewhere)', () {
      final a = resolveToolbarActions([_m(id: '1', isDeleted: true)]);
      expect(a.showForward, isTrue);
    });
  });

  // ── F-M6: showEdit ────────────────────────────────────────────────────────────

  group('resolveToolbarActions – showEdit', () {
    final base = DateTime.utc(2026, 6, 1, 12); // fixed "now" for edit tests

    test('single mine text non-deleted within window → showEdit true', () {
      final a = resolveToolbarActions(
        [_m(id: '1', isMine: true, createdAt: base.subtract(const Duration(minutes: 10)))],
        now: base,
      );
      expect(a.showEdit, isTrue);
    });

    test('exactly at 15-min boundary → showEdit true (inclusive)', () {
      final a = resolveToolbarActions(
        [_m(id: '1', isMine: true, createdAt: base.subtract(const Duration(minutes: 15)))],
        now: base,
      );
      expect(a.showEdit, isTrue,
          reason: 'exactly at editWindow boundary must still show Edit');
    });

    test('one second past 15-min boundary → showEdit false', () {
      final a = resolveToolbarActions(
        [
          _m(
            id: '1',
            isMine: true,
            createdAt: base.subtract(
                const Duration(minutes: 15, seconds: 1)),
          )
        ],
        now: base,
      );
      expect(a.showEdit, isFalse,
          reason: 'just past editWindow → Edit must be hidden');
    });

    test("other's message → showEdit false (isMine guard)", () {
      final a = resolveToolbarActions(
        [_m(id: '1', isMine: false, createdAt: base.subtract(const Duration(minutes: 1)))],
        now: base,
      );
      expect(a.showEdit, isFalse);
    });

    test('non-text message → showEdit false (type guard)', () {
      final a = resolveToolbarActions(
        [
          _m(
            id: '1',
            isMine: true,
            type: MessageType.image,
            createdAt: base.subtract(const Duration(minutes: 1)),
          )
        ],
        now: base,
      );
      expect(a.showEdit, isFalse);
    });

    test('deleted (tombstone) → showEdit false (!deleted guard)', () {
      final a = resolveToolbarActions(
        [
          _m(
            id: '1',
            isMine: true,
            isDeleted: true,
            createdAt: base.subtract(const Duration(minutes: 1)),
          )
        ],
        now: base,
      );
      expect(a.showEdit, isFalse);
    });

    test('multiple selection → showEdit false (single guard)', () {
      final a = resolveToolbarActions(
        [
          _m(id: '1', isMine: true, createdAt: base.subtract(const Duration(minutes: 1))),
          _m(id: '2', isMine: true, createdAt: base.subtract(const Duration(minutes: 2))),
        ],
        now: base,
      );
      expect(a.showEdit, isFalse);
    });
  });

  // ── F-M6: isForwardEligible ───────────────────────────────────────────────────

  group('isForwardEligible', () {
    ConversationSummary makeConv({
      required ConversationStatus status,
      required bool isRequest,
    }) =>
        ConversationSummary(
          id: 'c1',
          status: status,
          isRequest: isRequest,
          otherUser: const ConversationUser(userId: 'u2', fullName: 'Test'),
          unreadCount: 0,
        );

    test('accepted conversation, any count → eligible', () {
      final c = makeConv(status: ConversationStatus.accepted, isRequest: false);
      expect(isForwardEligible(c, 5), isTrue);
    });

    test('pending + caller is initiator (!isRequest) + count > 1 → NOT eligible', () {
      final c = makeConv(status: ConversationStatus.pending, isRequest: false);
      expect(isForwardEligible(c, 2), isFalse);
    });

    test('pending + caller is initiator + count == 1 → eligible (one-message rule)', () {
      final c = makeConv(status: ConversationStatus.pending, isRequest: false);
      expect(isForwardEligible(c, 1), isTrue,
          reason: 'backend allows single-message forward to pending-initiator conv');
    });

    test('pending + caller is receiver (isRequest=true) + count > 1 → eligible', () {
      final c = makeConv(status: ConversationStatus.pending, isRequest: true);
      expect(isForwardEligible(c, 5), isTrue);
    });
  });

  // ── M3: systemMessageText (Part 4) ────────────────────────────────────────────

  group('systemMessageText', () {
    test('mine + pinned → "You pinned a message"', () {
      expect(
        systemMessageText(
            eventType: SystemEventType.messagePinned,
            isMine: true,
            otherName: 'Ada'),
        MessagingStrings.systemYouPinned,
      );
    });

    test('other + pinned → "{name} pinned a message"', () {
      expect(
        systemMessageText(
            eventType: SystemEventType.messagePinned,
            isMine: false,
            otherName: 'Ada'),
        MessagingStrings.systemOtherPinned('Ada'),
      );
    });

    test('mine + unpinned → "You unpinned a message"', () {
      expect(
        systemMessageText(
            eventType: SystemEventType.messageUnpinned,
            isMine: true,
            otherName: 'Ada'),
        MessagingStrings.systemYouUnpinned,
      );
    });

    test('other + unpinned → "{name} unpinned a message"', () {
      expect(
        systemMessageText(
            eventType: SystemEventType.messageUnpinned,
            isMine: false,
            otherName: 'Ada'),
        MessagingStrings.systemOtherUnpinned('Ada'),
      );
    });

    test('null eventType → empty string (widget renders nothing)', () {
      expect(
        systemMessageText(eventType: null, isMine: true, otherName: 'Ada'),
        isEmpty,
      );
    });
  });

  // ── M3: clampPinIndex (Part 5) ────────────────────────────────────────────────

  group('clampPinIndex', () {
    test('empty list → 0', () => expect(clampPinIndex(3, 0), 0));
    test('in range → unchanged', () => expect(clampPinIndex(1, 3), 1));
    test('past end → last index', () => expect(clampPinIndex(5, 3), 2));
    test('negative → 0', () => expect(clampPinIndex(-2, 3), 0));
    test('removed shown pin (index==len) clamps down',
        () => expect(clampPinIndex(3, 3), 2));
  });

  // ── M3: resolvePinSegments (Part 5) ───────────────────────────────────────────

  group('resolvePinSegments', () {
    test('one pin → one segment, active 0', () {
      final s = resolvePinSegments(1, 0);
      expect(s.count, 1);
      expect(s.activeIndex, 0);
    });

    test('four pins, showing the third → active index 2', () {
      final s = resolvePinSegments(4, 2);
      expect(s.count, 4);
      expect(s.activeIndex, 2);
    });

    test('count is capped at the pin cap (4)', () {
      final s = resolvePinSegments(9, 0);
      expect(s.count, 4);
    });

    test('out-of-range index is clamped, never throws', () {
      final s = resolvePinSegments(3, 9);
      expect(s.count, 3);
      expect(s.activeIndex, 2);
    });

    test('zero pins → no segments', () {
      final s = resolvePinSegments(0, 0);
      expect(s.count, 0);
      expect(s.activeIndex, 0);
    });
  });
}