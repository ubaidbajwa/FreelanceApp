// F-M11 M7 played receipts — the two pure decision functions in message_actions.dart:
//   shouldMarkPlayed   — send a played receipt when the caller starts a note?
//   resolvePlayedBadge — which "played" fact the mic badge reflects (the asymmetry)
//
// Resume-after-pause is deliberately NOT modelled here: it is excluded at the call
// site (VoiceBubble only fires markPlayed on a fresh playback start), not by these
// functions. So there is no "resume" case to test at this layer.

import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer_frontend/features/messaging/application/chat_notifier.dart';
import 'package:freelancer_frontend/features/messaging/application/message_actions.dart';
import 'package:freelancer_frontend/features/messaging/data/models/messaging_models.dart';

ChatMessage _m({
  bool isMine = false,
  MessageType type = MessageType.voice,
  bool isDeleted = false,
  bool playedByMe = false,
  bool playedByOther = false,
}) =>
    ChatMessage(
      id: 'm',
      senderId: isMine ? '' : 'other',
      body: '',
      type: type,
      createdAt: DateTime.utc(2026, 1, 1),
      status: ChatSendStatus.confirmed,
      isMine: isMine,
      isDeleted: isDeleted,
      playedByMe: playedByMe,
      playedByOther: playedByOther,
    );

void main() {
  // ── shouldMarkPlayed ─────────────────────────────────────────────────────────
  // Own / non-voice / tombstone / already-played all skip; a fresh incoming voice
  // note that hasn't been marked is the only "yes".
  group('shouldMarkPlayed', () {
    test('incoming voice, not yet played → true', () {
      expect(shouldMarkPlayed(_m(isMine: false, playedByMe: false)), isTrue);
    });

    test("own note → false (server 400; a receipt about myself is meaningless)", () {
      expect(shouldMarkPlayed(_m(isMine: true)), isFalse);
    });

    test('incoming but non-voice (text) → false', () {
      expect(
        shouldMarkPlayed(_m(isMine: false, type: MessageType.text)),
        isFalse,
      );
    });

    test('incoming but non-voice (image) → false', () {
      expect(
        shouldMarkPlayed(_m(isMine: false, type: MessageType.image)),
        isFalse,
      );
    });

    test('incoming voice tombstone → false (deleted note has nothing to play)', () {
      expect(
        shouldMarkPlayed(_m(isMine: false, isDeleted: true)),
        isFalse,
      );
    });

    test('incoming voice already played → false (idempotent, no pointless call)', () {
      expect(
        shouldMarkPlayed(_m(isMine: false, playedByMe: true)),
        isFalse,
      );
    });
  });

  // ── resolvePlayedBadge ───────────────────────────────────────────────────────
  // Incoming note reads playedByMe; own note reads playedByOther. The cross-checks
  // are the important ones: the WRONG flag must never light the badge.
  group('resolvePlayedBadge', () {
    test('incoming, playedByMe true → played', () {
      expect(
        resolvePlayedBadge(_m(isMine: false, playedByMe: true)),
        PlayedBadgeState.played,
      );
    });

    test('incoming, playedByMe false → unplayed', () {
      expect(
        resolvePlayedBadge(_m(isMine: false, playedByMe: false)),
        PlayedBadgeState.unplayed,
      );
    });

    test('own, playedByOther true → played', () {
      expect(
        resolvePlayedBadge(_m(isMine: true, playedByOther: true)),
        PlayedBadgeState.played,
      );
    });

    test('own, playedByOther false → unplayed', () {
      expect(
        resolvePlayedBadge(_m(isMine: true, playedByOther: false)),
        PlayedBadgeState.unplayed,
      );
    });

    test('incoming badge IGNORES playedByOther (never crossed)', () {
      // The other person listening to a note must not light MY incoming badge.
      expect(
        resolvePlayedBadge(
            _m(isMine: false, playedByMe: false, playedByOther: true)),
        PlayedBadgeState.unplayed,
      );
    });

    test('own badge IGNORES playedByMe (never crossed)', () {
      // My own play state must not light my OWN note's "they listened" badge.
      expect(
        resolvePlayedBadge(
            _m(isMine: true, playedByOther: false, playedByMe: true)),
        PlayedBadgeState.unplayed,
      );
    });
  });
}
