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
  ChatSendStatus status = ChatSendStatus.confirmed,
}) =>
    ChatMessage(
      id: id,
      senderId: isMine ? '' : 'other',
      body: 'body',
      type: type,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      status: status,
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

  // ── M4: resolveTickState (read receipts) ──────────────────────────────────────
  // Three states only: none / sent (single ✓) / read (double ✓✓). No "delivered".
  // A message is read when createdAt <= otherLastReadAt, compared in UTC. Ticks
  // render on the caller's OWN confirmed messages only — never on the other
  // person's, system notices, tombstones, or optimistic (pending/failed) bubbles.
  group('resolveTickState', () {
    // Fixed watermark instant used across cases (UTC).
    final watermark = DateTime.utc(2026, 8, 31, 12, 0, 0);

    test("other's message → none (ticks are own-only)", () {
      final s = resolveTickState(
        _m(isMine: false, createdAt: watermark.subtract(const Duration(hours: 1))),
        watermark,
      );
      expect(s, TickState.none);
    });

    test('system message → none (never on system notices)', () {
      final s = resolveTickState(
        _m(isMine: true, type: MessageType.system, createdAt: watermark),
        watermark,
      );
      expect(s, TickState.none);
    });

    test('tombstone (deleted) → none', () {
      final s = resolveTickState(
        _m(isMine: true, isDeleted: true, createdAt: watermark),
        watermark,
      );
      expect(s, TickState.none);
    });

    test('pending optimistic bubble → none (keeps its clock)', () {
      final s = resolveTickState(
        _m(isMine: true, status: ChatSendStatus.pending, createdAt: watermark),
        watermark,
      );
      expect(s, TickState.none);
    });

    test('failed send → none (keeps its retry affordance)', () {
      final s = resolveTickState(
        _m(isMine: true, status: ChatSendStatus.failed, createdAt: watermark),
        watermark,
      );
      expect(s, TickState.none);
    });

    test('own confirmed, otherLastReadAt null → sent (nothing read yet)', () {
      final s = resolveTickState(_m(isMine: true, createdAt: watermark), null);
      expect(s, TickState.sent);
    });

    test('own confirmed, created before watermark → read', () {
      final s = resolveTickState(
        _m(isMine: true, createdAt: watermark.subtract(const Duration(minutes: 1))),
        watermark,
      );
      expect(s, TickState.read);
    });

    test('own confirmed, created after watermark → sent', () {
      final s = resolveTickState(
        _m(isMine: true, createdAt: watermark.add(const Duration(minutes: 1))),
        watermark,
      );
      expect(s, TickState.sent);
    });

    test('BOUNDARY: createdAt exactly equals watermark → read (inclusive)', () {
      final s = resolveTickState(_m(isMine: true, createdAt: watermark), watermark);
      expect(s, TickState.read,
          reason: 'createdAt <= otherLastReadAt is read; the boundary counts');
    });

    test('comparison is by instant, not wall-clock: a local-zone createdAt at the '
        'same instant as a UTC watermark is still read', () {
      // Same absolute instant expressed two ways. If the function ever compared
      // wall-clock components after a .toLocal(), this would flip for non-UTC
      // machines. Instant comparison keeps it correct everywhere.
      final createdLocal = watermark.toLocal();
      final s = resolveTickState(_m(isMine: true, createdAt: createdLocal), watermark);
      expect(s, TickState.read);
    });
  });

  // ── F-M7: reactions ───────────────────────────────────────────────────────────

  // Build a reaction bucket. `mine` = reactedByMe (caller-relative display flag).
  MessageReaction mkReaction(String emoji, int count, {bool mine = false}) =>
      MessageReaction(emoji: emoji, count: count, reactedByMe: mine);

  MessageReaction? findReaction(List<MessageReaction> rs, String emoji) {
    for (final r in rs) {
      if (r.emoji == emoji) return r;
    }
    return null;
  }

  // Part 1 — the reaction bar is a SINGLE-selection affordance and must never be
  // reachable for a system notice or a tombstone (those cannot be selected at all).
  group('shouldShowReactionBar', () {
    test('exactly one normal message selected → true', () {
      expect(shouldShowReactionBar([_m(id: '1')]), isTrue);
    });

    test('own message selected → true (no isMine restriction)', () {
      expect(shouldShowReactionBar([_m(id: '1', isMine: true)]), isTrue);
    });

    test('two messages selected → false (react-to-many is not a thing)', () {
      expect(shouldShowReactionBar([_m(id: '1'), _m(id: '2')]), isFalse);
    });

    test('empty selection → false', () {
      expect(shouldShowReactionBar([]), isFalse);
    });

    test('single tombstone → false (cannot be reacted to)', () {
      expect(shouldShowReactionBar([_m(id: '1', isDeleted: true)]), isFalse);
    });

    test('single system notice → false (cannot be reacted to)', () {
      expect(
        shouldShowReactionBar([_m(id: '1', type: MessageType.system)]),
        isFalse,
      );
    });
  });

  // Part 3/4 — the optimistic toggle. One call covers add / remove / replace, and
  // the local math must match what the backend's PUT does before the round trip.
  group('applyReactionToggle', () {
    test('no prior reaction, tap 👍 → new bucket count 1, mine, myEmoji 👍', () {
      final s = applyReactionToggle(const [], null, '👍');
      expect(s.myEmoji, '👍');
      final b = findReaction(s.reactions, '👍')!;
      expect(b.count, 1);
      expect(b.reactedByMe, isTrue);
    });

    test('add 👍 where two others already reacted → count 3, mine', () {
      final s = applyReactionToggle([mkReaction('👍', 2)], null, '👍');
      expect(s.myEmoji, '👍');
      expect(findReaction(s.reactions, '👍')!.count, 3);
      expect(findReaction(s.reactions, '👍')!.reactedByMe, isTrue);
    });

    test('toggle OFF my only 👍 (count 1) → bucket removed, myEmoji null', () {
      final s = applyReactionToggle([mkReaction('👍', 1, mine: true)], '👍', '👍');
      expect(s.myEmoji, isNull);
      expect(findReaction(s.reactions, '👍'), isNull);
    });

    test('toggle OFF my 👍 among 3 → count 2, no longer mine, myEmoji null', () {
      final s = applyReactionToggle([mkReaction('👍', 3, mine: true)], '👍', '👍');
      expect(s.myEmoji, isNull);
      final b = findReaction(s.reactions, '👍')!;
      expect(b.count, 2);
      expect(b.reactedByMe, isFalse);
    });

    test('replace 👍 (mine, count 1) with ❤️ → 👍 removed, ❤️ new count 1 mine', () {
      final s = applyReactionToggle([mkReaction('👍', 1, mine: true)], '👍', '❤️');
      expect(s.myEmoji, '❤️');
      expect(findReaction(s.reactions, '👍'), isNull);
      expect(findReaction(s.reactions, '❤️')!.count, 1);
      expect(findReaction(s.reactions, '❤️')!.reactedByMe, isTrue);
    });

    test('replace 👍 (mine, count 2) with existing ❤️ (count 1) → 👍 1 not-mine, ❤️ 2 mine', () {
      final s = applyReactionToggle(
        [mkReaction('👍', 2, mine: true), mkReaction('❤️', 1)],
        '👍',
        '❤️',
      );
      expect(s.myEmoji, '❤️');
      expect(findReaction(s.reactions, '👍')!.count, 1);
      expect(findReaction(s.reactions, '👍')!.reactedByMe, isFalse);
      expect(findReaction(s.reactions, '❤️')!.count, 2);
      expect(findReaction(s.reactions, '❤️')!.reactedByMe, isTrue);
    });
  });

  // Part 5 — merging an incoming ReactionChanged. Counts are authoritative from the
  // payload; reactedByMe is caller-relative and STRIPPED, so it must be re-derived
  // from the caller's own tracked emoji — never from the event.
  group('mergeReactionCounts', () {
    test('caller reacted 👍; event says 👍 count 2 (someone else too) → 2, mine', () {
      final merged = mergeReactionCounts([mkReaction('👍', 2)], '👍');
      final b = findReaction(merged, '👍')!;
      expect(b.count, 2);
      expect(b.reactedByMe, isTrue,
          reason: 'the event strips reactedByMe; re-derive it from myEmoji');
    });

    test('caller removed 👍 (myEmoji null) while event in flight → 👍 not mine', () {
      final merged = mergeReactionCounts([mkReaction('👍', 2)], null);
      expect(findReaction(merged, '👍')!.reactedByMe, isFalse);
    });

    test('event for an emoji the caller never used → that bucket not mine, own stays mine', () {
      final merged = mergeReactionCounts([mkReaction('😂', 1), mkReaction('👍', 1)], '👍');
      expect(findReaction(merged, '😂')!.reactedByMe, isFalse);
      expect(findReaction(merged, '👍')!.reactedByMe, isTrue);
    });

    test('counts come straight from the payload (no double-count of an optimistic add)', () {
      // The caller already applied 👍 optimistically (count included by server).
      // The event carries the SAME authoritative count — merge must not add again.
      final merged = mergeReactionCounts([mkReaction('👍', 1)], '👍');
      expect(findReaction(merged, '👍')!.count, 1);
    });
  });
}