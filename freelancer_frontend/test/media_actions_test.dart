// Pure media decision logic (F-M5) — the layout/validation/preview functions that
// live OUTSIDE the widget tree in message_actions.dart. Each is a client-side mirror
// of a server rule (size/type limits) or a deterministic display calc (box, preview,
// duration) — so every one is a plain tested function here, not scattered widget ifs.

import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer_frontend/features/messaging/application/message_actions.dart';
import 'package:freelancer_frontend/features/messaging/data/models/messaging_models.dart';
import 'package:freelancer_frontend/features/messaging/messaging_strings.dart';

// A conversation-list row. Only the two fields resolveConversationPreview reads
// (lastMessagePreview + lastMessageType) vary per case; the rest are fixed.
ConversationSummary _conv({
  String? preview,
  MessageType? type,
}) =>
    ConversationSummary(
      id: 'c1',
      status: ConversationStatus.accepted,
      isRequest: false,
      otherUser: const ConversationUser(userId: 'u2', fullName: 'Test'),
      lastMessagePreview: preview,
      lastMessageType: type,
    );

void main() {
  // ── resolveMediaBox ────────────────────────────────────────────────────────────
  // Preserve the server aspect ratio; fit within maxWidth first, then clamp height.
  // Unknown dimensions → a stable square at the smaller side so the list never
  // reflows once the real asset loads.
  group('resolveMediaBox', () {
    const maxW = 250.0;
    const maxH = 300.0;

    test('wide image → width pinned to maxWidth, height scaled by ratio', () {
      final box = resolveMediaBox(
        mediaWidth: 400,
        mediaHeight: 200, // aspect 2:1
        maxWidth: maxW,
        maxHeight: maxH,
      );
      expect(box.width, closeTo(250, 0.001));
      expect(box.height, closeTo(125, 0.001)); // 250 / 2
      expect(box.width, lessThanOrEqualTo(maxW));
      expect(box.height, lessThanOrEqualTo(maxH));
    });

    test('tall image → height clamped to maxHeight, width scaled by ratio', () {
      final box = resolveMediaBox(
        mediaWidth: 200,
        mediaHeight: 400, // aspect 1:2 → naive height 500 > maxHeight
        maxWidth: maxW,
        maxHeight: maxH,
      );
      expect(box.height, closeTo(300, 0.001)); // clamped to maxHeight
      expect(box.width, closeTo(150, 0.001)); // 300 * 0.5
      expect(box.width, lessThanOrEqualTo(maxW));
      expect(box.height, lessThanOrEqualTo(maxH));
    });

    test('square image → width at maxWidth, equal height', () {
      final box = resolveMediaBox(
        mediaWidth: 300,
        mediaHeight: 300,
        maxWidth: maxW,
        maxHeight: maxH,
      );
      expect(box.width, closeTo(250, 0.001));
      expect(box.height, closeTo(250, 0.001));
    });

    test('unknown dimensions (null) → square fallback at the smaller side', () {
      final box = resolveMediaBox(
        mediaWidth: null,
        mediaHeight: null,
        maxWidth: maxW,
        maxHeight: maxH,
      );
      expect(box.width, closeTo(250, 0.001)); // min(250, 300)
      expect(box.height, closeTo(250, 0.001));
    });

    test('non-positive dimensions → square fallback (guards divide-by-zero)', () {
      final box = resolveMediaBox(
        mediaWidth: 0,
        mediaHeight: -5,
        maxWidth: maxW,
        maxHeight: maxH,
      );
      expect(box.width, closeTo(250, 0.001));
      expect(box.height, closeTo(250, 0.001));
    });

    test('cap is respected on BOTH axes regardless of ratio', () {
      for (final dims in [
        [1000, 100], // very wide
        [100, 1000], // very tall
        [1, 1], // tiny square
      ]) {
        final box = resolveMediaBox(
          mediaWidth: dims[0],
          mediaHeight: dims[1],
          maxWidth: maxW,
          maxHeight: maxH,
        );
        expect(box.width, lessThanOrEqualTo(maxW + 0.001));
        expect(box.height, lessThanOrEqualTo(maxH + 0.001));
      }
    });
  });

  // ── mediaKindForPath ─────────────────────────────────────────────────────────
  // Extension → kind. Images: jpg/jpeg/png/webp/gif. Videos: mp4/webm/mov/qt.
  group('mediaKindForPath', () {
    test('each supported image extension → image', () {
      for (final ext in ['jpg', 'jpeg', 'png', 'webp', 'gif']) {
        expect(mediaKindForPath('/tmp/pic.$ext'), PickedMediaKind.image,
            reason: '.$ext should be an image');
      }
    });

    test('each supported video extension → video', () {
      for (final ext in ['mp4', 'webm', 'mov', 'qt']) {
        expect(mediaKindForPath('/tmp/clip.$ext'), PickedMediaKind.video,
            reason: '.$ext should be a video');
      }
    });

    test('unknown extension → null', () {
      expect(mediaKindForPath('/tmp/notes.txt'), isNull);
    });

    test('uppercase extension is matched case-insensitively', () {
      expect(mediaKindForPath('/tmp/PHOTO.PNG'), PickedMediaKind.image);
      expect(mediaKindForPath('/tmp/MOVIE.MP4'), PickedMediaKind.video);
    });

    test('path with no extension → null', () {
      expect(mediaKindForPath('/tmp/filename'), isNull);
    });
  });

  // ── validateMediaFile ────────────────────────────────────────────────────────
  // Client-side mirror of the server size/type limits: image ≤ 10 MB, video ≤ 50 MB.
  // Returns null when acceptable, else the specific user-facing limit message.
  group('validateMediaFile', () {
    const mb = 1024 * 1024;

    test('unsupported type → unsupported-type message', () {
      expect(
        validateMediaFile(path: '/tmp/doc.pdf', lengthBytes: 1),
        MessagingStrings.mediaUnsupportedType,
      );
    });

    test('image over 10 MB → image-too-large message', () {
      expect(
        validateMediaFile(path: '/tmp/pic.jpg', lengthBytes: 10 * mb + 1),
        MessagingStrings.mediaImageTooLarge(),
      );
    });

    test('video over 50 MB → video-too-large message', () {
      expect(
        validateMediaFile(path: '/tmp/clip.mp4', lengthBytes: 50 * mb + 1),
        MessagingStrings.mediaVideoTooLarge(),
      );
    });

    test('image just under its limit → accepted (null)', () {
      expect(
        validateMediaFile(path: '/tmp/pic.png', lengthBytes: 10 * mb),
        isNull,
      );
    });

    test('video just under its limit → accepted (null)', () {
      expect(
        validateMediaFile(path: '/tmp/clip.mov', lengthBytes: 50 * mb),
        isNull,
      );
    });

    test('the limit is applied PER KIND: a 20 MB video passes', () {
      expect(
        validateMediaFile(path: '/tmp/clip.mp4', lengthBytes: 20 * mb),
        isNull,
      );
    });

    test('the limit is applied PER KIND: a 20 MB image does NOT pass', () {
      expect(
        validateMediaFile(path: '/tmp/pic.jpg', lengthBytes: 20 * mb),
        MessagingStrings.mediaImageTooLarge(),
      );
    });
  });

  // ── formatMediaDuration ──────────────────────────────────────────────────────
  // m:ss clock format (western digits, zero-padded seconds). Null/negative → 0:00.
  group('formatMediaDuration', () {
    test('zero → 0:00', () => expect(formatMediaDuration(0), '0:00'));

    test('under a minute → 0:ss (seconds zero-padded)',
        () => expect(formatMediaDuration(7000), '0:07'));

    test('exactly a minute → 1:00',
        () => expect(formatMediaDuration(60000), '1:00'));

    test('over ten minutes → mm:ss with no minute padding',
        () => expect(formatMediaDuration(11 * 60000 + 5000), '11:05'));

    test('seconds field is always two digits',
        () => expect(formatMediaDuration(65000), '1:05'));

    test('null → 0:00 (never throws)',
        () => expect(formatMediaDuration(null), '0:00'));

    test('negative → 0:00 (clamped, never throws)',
        () => expect(formatMediaDuration(-1), '0:00'));
  });

  // ── resolveConversationPreview ───────────────────────────────────────────────
  // A present caption/text wins; an uncaptioned media message resolves to the
  // localised "Photo"/"Video"/"Voice message"; no message at all → "No messages yet".
  group('resolveConversationPreview', () {
    test('caption present → caption wins', () {
      expect(
        resolveConversationPreview(_conv(preview: 'hello there')),
        'hello there',
      );
    });

    test('empty caption + image type → localised Photo', () {
      expect(
        resolveConversationPreview(_conv(preview: '', type: MessageType.image)),
        MessagingStrings.listPhoto,
      );
    });

    test('empty caption + video type → localised Video', () {
      expect(
        resolveConversationPreview(_conv(preview: '', type: MessageType.video)),
        MessagingStrings.listVideo,
      );
    });

    test('empty caption + voice type → localised Voice message', () {
      expect(
        resolveConversationPreview(_conv(preview: '', type: MessageType.voice)),
        MessagingStrings.listVoice,
      );
    });

    test('no message at all (null preview + null type) → No messages yet', () {
      expect(
        resolveConversationPreview(_conv()),
        MessagingStrings.noMessagesYet,
      );
    });

    test('caption is preferred over the media label', () {
      // Both a caption AND an image type present → the caption text wins, never
      // the "Photo" label.
      expect(
        resolveConversationPreview(
            _conv(preview: 'look at this', type: MessageType.image)),
        'look at this',
      );
    });
  });
}
