// Pure voice-note decision logic (F-M11) from message_actions.dart. Amplitude→level
// mapping, waveform downsample/parse, the hold-drag cancel/lock resolver, and the
// composer mic/send switch are all deterministic pure functions — kept out of the
// widget tree so the conditional core is tested here directly.

import 'dart:ui' show TextDirection;

import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer_frontend/features/messaging/application/message_actions.dart';

void main() {
  // ── downsampleWaveform ───────────────────────────────────────────────────────
  // Collected 0–100 samples → at most maxSamples (default 64), comma-separated for
  // the wire. Empty → '' (caller sends no waveform). Values clamped to 0–100.
  group('downsampleWaveform', () {
    test('fewer than 64 samples → kept verbatim', () {
      final samples = [10, 20, 30, 40, 50];
      expect(downsampleWaveform(samples), '10,20,30,40,50');
    });

    test('far more than 64 samples → exactly 64 buckets, all in 0–100 range', () {
      final samples = [for (var i = 0; i < 500; i++) i % 101];
      final out = downsampleWaveform(samples);
      final parts = out.split(',');
      expect(parts.length, 64);
      for (final p in parts) {
        final v = int.parse(p);
        expect(v, inInclusiveRange(0, 100));
      }
    });

    test('all-silent input → a valid string of zeros (never empty/malformed)', () {
      final samples = [for (var i = 0; i < 200; i++) 0];
      final out = downsampleWaveform(samples);
      expect(out, isNotEmpty);
      final parts = out.split(',');
      expect(parts.length, 64);
      expect(parts.every((p) => int.parse(p) == 0), isTrue);
    });

    test('single sample → that value', () {
      expect(downsampleWaveform([42]), '42');
    });

    test('empty list → empty string', () {
      expect(downsampleWaveform([]), '');
    });

    test('out-of-range values are clamped to 0–100', () {
      // Under maxSamples so values pass through verbatim except for the clamp.
      expect(downsampleWaveform([-10, 0, 50, 100, 250]), '0,0,50,100,100');
    });
  });

  // ── amplitudeToLevel ─────────────────────────────────────────────────────────
  // dBFS (0 loudest, negative quieter) → 0–100. Below floor → 0; ≥ 0 dBFS → 100.
  group('amplitudeToLevel', () {
    test('silence (at/below the noise floor) → 0', () {
      expect(amplitudeToLevel(-45.0), 0); // exactly the floor
      expect(amplitudeToLevel(-60.0), 0); // below the floor
    });

    test('maximum (0 dBFS) → 100', () {
      expect(amplitudeToLevel(0.0), 100);
    });

    test('a mid value maps proportionally', () {
      // floor -45 → halfway (-22.5) is 50.
      expect(amplitudeToLevel(-22.5), 50);
    });

    test('positive dBFS (out of range high) is clamped to 100', () {
      expect(amplitudeToLevel(12.0), 100);
    });

    test('far below floor (out of range low) is clamped to 0', () {
      expect(amplitudeToLevel(-200.0), 0);
    });

    test('NaN / infinite readings degrade to 0, never escape the range', () {
      // The isNaN/isInfinite guard runs FIRST, so every non-finite reading maps to
      // 0 — even +infinity does NOT fall through to the ≥ 0 → 100 branch.
      expect(amplitudeToLevel(double.nan), 0);
      expect(amplitudeToLevel(double.infinity), 0);
      expect(amplitudeToLevel(double.negativeInfinity), 0);
    });
  });

  // ── parseWaveform ────────────────────────────────────────────────────────────
  // Server string → 0–100 levels. Null/empty → []; malformed entries skipped
  // defensively (never throws); values clamped.
  group('parseWaveform', () {
    test('valid string → list of ints', () {
      expect(parseWaveform('10,20,30'), [10, 20, 30]);
    });

    test('null → empty list', () {
      expect(parseWaveform(null), isEmpty);
    });

    test('empty string → empty list', () {
      expect(parseWaveform(''), isEmpty);
    });

    test('malformed entries degrade gracefully (skipped, never throws)', () {
      expect(parseWaveform('10,abc,,30'), [10, 30]);
    });

    test('fully malformed string → empty list (never throws)', () {
      expect(parseWaveform('x,y,z'), isEmpty);
    });

    test('out-of-range values are clamped to 0–100', () {
      expect(parseWaveform('-5,50,250'), [0, 50, 100]);
    });
  });

  // ── resolveRecordingDrag ─────────────────────────────────────────────────────
  // Hold-drag → none / cancel / lock. Horizontal intent is "toward the start edge"
  // so it mirrors under RTL. On a diagonal, the axis further along its own threshold
  // ratio wins; on a tie, LOCK wins (non-destructive by design).
  group('resolveRecordingDrag', () {
    const t = 80.0; // both default thresholds

    test('neither threshold crossed → none', () {
      final o = resolveRecordingDrag(
        dragX: -10,
        dragY: -10,
        direction: TextDirection.ltr,
      );
      expect(o, RecordDragOutcome.none);
    });

    test('horizontal only (toward start edge) → cancel', () {
      final o = resolveRecordingDrag(
        dragX: -(t + 20), // LTR: leftward is startward
        dragY: 0,
        direction: TextDirection.ltr,
      );
      expect(o, RecordDragOutcome.cancel);
    });

    test('vertical only (upward) → lock', () {
      final o = resolveRecordingDrag(
        dragX: 0,
        dragY: -(t + 20),
        direction: TextDirection.ltr,
      );
      expect(o, RecordDragOutcome.lock);
    });

    test('both crossed, horizontal further along its ratio → cancel', () {
      final o = resolveRecordingDrag(
        dragX: -160, // ratio 2.0
        dragY: -80, // ratio 1.0
        direction: TextDirection.ltr,
      );
      expect(o, RecordDragOutcome.cancel);
    });

    test('both crossed, vertical further along its ratio → lock', () {
      final o = resolveRecordingDrag(
        dragX: -80, // ratio 1.0
        dragY: -160, // ratio 2.0
        direction: TextDirection.ltr,
      );
      expect(o, RecordDragOutcome.lock);
    });

    test('exact tie → lock (the safe, non-destructive default)', () {
      final o = resolveRecordingDrag(
        dragX: -80, // ratio 1.0
        dragY: -80, // ratio 1.0
        direction: TextDirection.ltr,
      );
      expect(o, RecordDragOutcome.lock);
    });

    test('RTL: horizontal is measured toward the start edge (rightward cancels)',
        () {
      // In RTL the start edge is on the right, so a rightward (+dragX) drag is the
      // cancel gesture — the mirror image of LTR.
      final rtlCancel = resolveRecordingDrag(
        dragX: t + 20, // rightward = startward under RTL
        dragY: 0,
        direction: TextDirection.rtl,
      );
      expect(rtlCancel, RecordDragOutcome.cancel);

      // The same leftward drag that cancels under LTR must NOT cancel under RTL.
      final rtlNoCancel = resolveRecordingDrag(
        dragX: -(t + 20),
        dragY: 0,
        direction: TextDirection.rtl,
      );
      expect(rtlNoCancel, RecordDragOutcome.none);
    });
  });

  // ── resolveComposerAction ────────────────────────────────────────────────────
  // Empty (after trim) → mic (record); any text → send. NOTE: the function takes
  // only `text` — there is no editing-mode parameter, so "editing mode → send" is
  // handled by the caller, not testable here (reported).
  group('resolveComposerAction', () {
    test('empty text → mic', () {
      expect(resolveComposerAction(''), ComposerAction.mic);
    });

    test('one character → send', () {
      expect(resolveComposerAction('a'), ComposerAction.send);
    });

    test('whitespace only → mic (trimmed to empty)', () {
      expect(resolveComposerAction('   '), ComposerAction.mic);
    });

    test('cleared back to empty → mic (same as empty)', () {
      expect(resolveComposerAction(''), ComposerAction.mic);
    });
  });
}
