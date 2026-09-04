// Pure decision logic for selection-mode actions. Kept OUT of the widget tree
// on purpose (spec): which toolbar icons show, and which delete-dialog options
// apply, is the conditional core of this slice — one explicit tested function
// each, not scattered ifs.

import 'dart:ui' show TextDirection;

import '../data/models/messaging_models.dart';
import '../messaging_strings.dart';
import 'chat_notifier.dart';

// Delete-for-everyone has a 48-hour server-side window; older → backend 403.
// This constant drives a UI AFFORDANCE ONLY (hide the option early). The SERVER
// is authoritative — it re-checks and rejects regardless of what the UI shows.
const Duration deleteForEveryoneWindow = Duration(hours: 48);

// Edit window — 15-minute UI affordance only. Server re-checks and enforces on
// the PUT endpoint; this only hides the toolbar button before the window passes.
const Duration editWindow = Duration(minutes: 15);

// Whether a conversation is eligible as a forward target.
// The backend refuses the whole batch when the target is a Pending conversation
// where the caller is the initiator (status==pending && !isRequest) AND more than
// one message is being forwarded. Filter those out of the picker so the user
// never sees a target that will always be refused — a false affordance.
// NOTE: single-message forward to a pending-initiator conversation is still
// allowed by the backend (the one-message initiator rule), so we do not exclude
// those (messageCount == 1). The count matters.
bool isForwardEligible(ConversationSummary conv, int messageCount) {
  if (conv.status == ConversationStatus.pending &&
      !conv.isRequest &&
      messageCount > 1) {
    return false;
  }
  return true;
}

// Which toolbar icons apply to the current selection.
// Left-to-right display order: reply · edit · copy · forward · delete · pin.
class ToolbarActions {
  final bool showReply; // single non-deleted selection only (F-M5)
  final bool showEdit; // single, mine, text, !deleted, within editWindow (F-M6)
  final bool showCopy; // all selected are text AND none is a tombstone
  final bool showForward; // any non-empty selection (F-M6)
  final bool showDelete; // always, when selection non-empty
  final bool showPin; // single selection only
  final bool isUnpin; // single + already pinned → button means "unpin"

  const ToolbarActions({
    required this.showReply,
    required this.showEdit,
    required this.showCopy,
    required this.showForward,
    required this.showDelete,
    required this.showPin,
    required this.isUnpin,
  });
}

ToolbarActions resolveToolbarActions(
  List<ChatMessage> selected, {
  DateTime? now,
}) {
  if (selected.isEmpty) {
    return const ToolbarActions(
      showReply: false,
      showEdit: false,
      showCopy: false,
      showForward: false,
      showDelete: false,
      showPin: false,
      isUnpin: false,
    );
  }

  final current = (now ?? DateTime.now()).toUtc();

  // Copy: only when EVERY selected message has copyable text — hidden the moment
  // a non-text (image/file/voice) or a deleted tombstone is in the selection.
  final allCopyable =
      selected.every((m) => m.type == MessageType.text && !m.isDeleted);

  // Pin / Reply: single selection only.
  final single = selected.length == 1;

  // Reply: single non-deleted only. Tombstones cannot be selected (F-M4 guard),
  // but the check is kept for belt-and-suspenders correctness.
  final singleNonDeleted = single && !selected.first.isDeleted;

  // Edit: single, mine, text, !deleted, within 15-minute window (UI affordance).
  final editEligible = single &&
      selected.first.isMine &&
      selected.first.type == MessageType.text &&
      !selected.first.isDeleted &&
      current.difference(selected.first.createdAt.toUtc()) <= editWindow;

  return ToolbarActions(
    showReply: singleNonDeleted,
    showEdit: editEligible,
    showCopy: allCopyable,
    showForward: selected.isNotEmpty,
    showDelete: true,
    showPin: single,
    isUnpin: single && selected.first.isPinned,
  );
}

// Which options the delete dialog offers. "Delete for everyone" is only possible
// for the caller's OWN messages AND only within the 48h window — a single
// other's message, a mixed selection, or anything too old removes the option.
class DeleteOptions {
  final bool showDeleteForEveryone;
  final bool showDeleteForMe; // always true for a non-empty selection
  final int count;

  const DeleteOptions({
    required this.showDeleteForEveryone,
    required this.showDeleteForMe,
    required this.count,
  });
}

DeleteOptions resolveDeleteOptions(
  List<ChatMessage> selected, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toUtc();

  final allMine = selected.isNotEmpty && selected.every((m) => m.isMine);
  final allWithinWindow = selected.every(
    (m) => current.difference(m.createdAt.toUtc()) <= deleteForEveryoneWindow,
  );

  return DeleteOptions(
    showDeleteForEveryone: allMine && allWithinWindow,
    showDeleteForMe: selected.isNotEmpty,
    count: selected.length,
  );
}

// ── Read-receipt tick state (M4) ──────────────────────────────────────────────
// THREE states, not four. There is deliberately no "delivered" (grey ✓✓): the
// backend only knows a read WATERMARK, not per-device delivery, so faking an
// intermediate state would be a lie.
//   none → no tick at all
//   sent → single ✓ (server has it; the other side hasn't read yet)
//   read → double ✓✓ (createdAt <= otherLastReadAt)
enum TickState { none, sent, read }

// Decide the tick for ONE message given the other participant's read watermark.
// Pure + tested — the conditional core of the slice lives here, not in the widget.
//
// Ticks are the CALLER'S OWN, confirmed, real messages only: never the other
// person's, never system notices, never tombstones, and never optimistic
// (pending → clock, failed → retry) bubbles. `isMine` is read off the message —
// the same single source of truth the bubble itself uses — so a caller can never
// pass an isMine that disagrees with the message.
//
// The read comparison is done in UTC and ONLY here: `.toLocal()` must NOT be
// applied. DateTime.isAfter compares absolute instants, so converting first would
// change nothing about the instant — but it would invite a later "format/compare
// the day" bug that only shows for users off the server's offset. `.toUtc()` on
// both sides makes the intent explicit and normalises any stray non-UTC value.
TickState resolveTickState(ChatMessage message, DateTime? otherLastReadAt) {
  if (!message.isMine) return TickState.none;
  if (message.type == MessageType.system) return TickState.none;
  if (message.isDeleted) return TickState.none;
  if (message.status != ChatSendStatus.confirmed) return TickState.none;

  // Nothing read yet → the message is sent but not read.
  if (otherLastReadAt == null) return TickState.sent;

  final created = message.createdAt.toUtc();
  final watermark = otherLastReadAt.toUtc();
  // Read when createdAt <= watermark. The boundary (equal instant) counts as read.
  return created.isAfter(watermark) ? TickState.sent : TickState.read;
}

// ── Reactions (F-M7) ──────────────────────────────────────────────────────────

// The six quick reactions shown in the long-press bar, in display order. A NAMED
// constant (not inline in a widget) so the bar and the full picker's "recently
// offered" row share exactly one source of truth. Multi-codepoint (❤️ is
// emoji+VS16) is fine — the backend column is varchar(16).
const List<String> kQuickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

// Curated emoji grid for the full picker (Part 2 — Option B, no dependency). ~130
// common emoji in six groups, parallel to the reactionCat* labels in
// MessagingStrings (same order). No search / skin-tone / recents this slice
// (noted in docs/TODO.md). Multi-codepoint sequences fit the varchar(16) column.
const List<List<String>> kEmojiPickerGroups = [
  // Smileys & Emotion
  [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚',
    '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🥳',
    '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '😣', '😖', '😫',
    '😩', '🥺', '😢', '😭', '😤', '😠', '😡', '🤬', '😳', '🥵',
  ],
  // People & Gestures
  [
    '👍', '👎', '👊', '✊', '🤛', '🤜', '👏', '🙌', '👐', '🤲',
    '🤝', '🙏', '✍️', '💪', '👋', '🤚', '🖐️', '✋', '🖖', '👌',
    '🤌', '🤏', '✌️', '🤞', '🤟', '🤘', '👆', '👇', '👈', '👉',
  ],
  // Hearts & Symbols
  [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
    '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💯', '✨',
    '⭐', '🌟', '💫', '🔥', '🎉', '🎊', '✅', '❌', '❓', '❗',
  ],
  // Animals & Nature
  [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
    '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🦆', '🦉',
    '🦄', '🐝', '🦋', '🐢', '🐬', '🐳', '🌸', '🌻', '🌈', '🌙',
  ],
  // Food & Drink
  [
    '🍏', '🍎', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍑', '🥭',
    '🍍', '🥥', '🍅', '🥑', '🌶️', '🌽', '🥕', '🍞', '🧀', '🍗',
    '🍔', '🍟', '🍕', '🌮', '🍦', '🍩', '🍪', '🎂', '☕', '🍺',
  ],
  // Activities & Objects
  [
    '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🎱', '🏓', '🏸', '🥅',
    '🎯', '🎮', '🎲', '🎸', '🎹', '🎺', '🎧', '📱', '💻', '⌚',
    '📷', '💡', '🔑', '🎁', '📚', '✏️', '📌', '🏆', '🚗', '✈️',
  ],
];

// Whether the floating reaction bar may be shown for the current selection.
// It is a SINGLE-selection affordance: the moment a second message is selected it
// hides (reacting to many at once is not a thing). System notices and tombstones
// can never be selected (F-M4 guard), but we re-assert it here so the bar can
// never be reached for them even if a caller mis-wires the gesture.
bool shouldShowReactionBar(List<ChatMessage> selected) {
  if (selected.length != 1) return false;
  final m = selected.first;
  return !m.isDeleted && m.type != MessageType.system;
}

// The result of an optimistic reaction toggle: the new bucket list plus the
// caller's own emoji afterwards (null = the caller now has no reaction).
class ReactionState {
  final List<MessageReaction> reactions;
  final String? myEmoji;
  const ReactionState(this.reactions, this.myEmoji);
}

// Pure optimistic toggle — one function covering ADD / REMOVE / REPLACE, mirroring
// the backend PUT (one reaction per user; same emoji removes; different replaces).
// `myEmoji` is the caller's current reaction (null if none); `tapped` is the emoji
// they just tapped. Existing bucket order is preserved; a brand-new bucket is
// appended. A bucket that drops to zero is removed (a lone "0" is meaningless).
ReactionState applyReactionToggle(
  List<MessageReaction> current,
  String? myEmoji,
  String tapped,
) {
  final isToggleOff = myEmoji == tapped;
  final result = <MessageReaction>[];

  for (final r in current) {
    var count = r.count;
    var mine = r.reactedByMe;
    // Remove the caller's OLD contribution (whether toggling off or switching).
    if (myEmoji != null && r.emoji == myEmoji) {
      count -= 1;
      mine = false;
    }
    // Add the caller's NEW contribution to the tapped bucket (unless toggling off).
    if (!isToggleOff && r.emoji == tapped) {
      count += 1;
      mine = true;
    }
    if (count > 0) {
      result.add(
          MessageReaction(emoji: r.emoji, count: count, reactedByMe: mine));
    }
  }

  // Tapped an emoji that no bucket has yet → create it (count 1, mine).
  if (!isToggleOff && !current.any((r) => r.emoji == tapped)) {
    result.add(MessageReaction(emoji: tapped, count: 1, reactedByMe: true));
  }

  return ReactionState(result, isToggleOff ? null : tapped);
}

// Merge an incoming ReactionChanged event (Part 5). The event fans out to BOTH
// participants, so the backend strips reactedByMe (it is caller-relative). Counts
// are authoritative and taken as-is; reactedByMe is RE-DERIVED from the caller's
// own tracked emoji — never from the event — so an event never wipes the caller's
// highlight. Because the counts already include the caller's own reaction, a just-
// applied optimistic reaction is neither double-counted nor made to flicker.
List<MessageReaction> mergeReactionCounts(
  List<MessageReaction> incoming,
  String? myEmoji,
) {
  return incoming
      .map((r) => MessageReaction(
            emoji: r.emoji,
            count: r.count,
            reactedByMe: r.emoji == myEmoji,
          ))
      .toList();
}

// ── System message text (M3, Part 4) ─────────────────────────────────────────
// The server stores an EMPTY body for a System message on purpose: the sentence
// reads differently per viewer ("You" vs a name) and must be translatable, so
// the client builds it. `isMine` is the SAME signal the bubble uses
// (senderId != otherUserId) — a system message's sender is the actor, who in a
// 1:1 thread is necessarily the caller or the one other participant, so no new
// source of truth is needed. `otherName` is the other participant's display name.
// A null/unknown eventType yields an empty string (the widget renders nothing).
String systemMessageText({
  required SystemEventType? eventType,
  required bool isMine,
  required String otherName,
}) {
  return switch (eventType) {
    SystemEventType.messagePinned => isMine
        ? MessagingStrings.systemYouPinned
        : MessagingStrings.systemOtherPinned(otherName),
    SystemEventType.messageUnpinned => isMine
        ? MessagingStrings.systemYouUnpinned
        : MessagingStrings.systemOtherUnpinned(otherName),
    null => '',
  };
}

// ── Pin banner index clamp (M3, Part 5) ──────────────────────────────────────
// Keep the banner's current index in range after a pin is added or (crucially)
// removed. A removed pin can leave `pinnedIndex` pointing past the end; clamp
// rather than crash. Empty list → 0; otherwise pinned to [0, length-1].
int clampPinIndex(int index, int length) {
  if (length <= 0) return 0;
  if (index < 0) return 0;
  if (index >= length) return length - 1;
  return index;
}

// Segment-bar model for the pin banner (WhatsApp-style): how many thin segments
// to draw and which one is active. One segment per active pin, capped at the
// server's pin cap (4). The active index is clamped so a stale/out-of-range
// index never throws while rendering.
class PinSegments {
  final int count;
  final int activeIndex;
  const PinSegments({required this.count, required this.activeIndex});
}

PinSegments resolvePinSegments(int pinCount, int currentIndex) {
  final count = pinCount.clamp(0, MessagingStrings.pinnedMax);
  final active = count == 0 ? 0 : clampPinIndex(currentIndex, count);
  return PinSegments(count: count, activeIndex: active);
}

// ── Media (F-M5) ──────────────────────────────────────────────────────────────

// The picked-media kind, derived purely from the file extension. Image and Video
// are the only two kinds this slice sends (documents/voice are out of scope).
enum PickedMediaKind { image, video }

// Client-side media limits. These MIRROR the server (ChatService) and exist only to
// fail fast — making someone wait through a 45 MB upload only to get a 400 on a slow
// connection is a poor experience. The SERVER remains authoritative: it re-checks
// the size, the type (by magic bytes, not just extension), and the video duration,
// and rejects with a 400 naming the limit regardless of what passed here.
class MediaLimits {
  MediaLimits._();

  static const int maxImageBytes = MessagingStrings.mediaImageMaxMb * 1024 * 1024;
  static const int maxVideoBytes = MessagingStrings.mediaVideoMaxMb * 1024 * 1024;
  // Duration can't be checked reliably before upload (see note on validateMediaFile);
  // this mirrors the server's 120 s cap for reference only.
  static const int maxVideoDurationSeconds = MessagingStrings.mediaVideoMaxSeconds;

  static const Set<String> imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
  static const Set<String> videoExtensions = {'mp4', 'webm', 'mov', 'qt'};
}

// The media kind for a path by extension, or null if it is neither a supported
// image nor a supported video.
PickedMediaKind? mediaKindForPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  if (MediaLimits.imageExtensions.contains(ext)) return PickedMediaKind.image;
  if (MediaLimits.videoExtensions.contains(ext)) return PickedMediaKind.video;
  return null;
}

// Validate a picked file BEFORE uploading. Returns null when it is acceptable, or a
// user-facing message naming the specific limit that was exceeded. Size and type are
// checkable client-side; VIDEO DURATION is NOT (the frame/duration metadata isn't
// reliably available without decoding), so it is deliberately left to the server,
// which rejects an over-long video with a 400 the caller surfaces verbatim.
String? validateMediaFile({required String path, required int lengthBytes}) {
  final kind = mediaKindForPath(path);
  if (kind == null) return MessagingStrings.mediaUnsupportedType;
  if (kind == PickedMediaKind.image && lengthBytes > MediaLimits.maxImageBytes) {
    return MessagingStrings.mediaImageTooLarge();
  }
  if (kind == PickedMediaKind.video && lengthBytes > MediaLimits.maxVideoBytes) {
    return MessagingStrings.mediaVideoTooLarge();
  }
  return null;
}

// Conversation-list preview text (Part 7). A present caption/text wins; an
// uncaptioned media message (server sends an EMPTY preview + a LastMessageType)
// resolves to the localised "Photo"/"Video" — the label is never stored server-side
// because it can't be translated. No message at all → "No messages yet".
//
// Returns text only; the tile adds the small leading icon from lastMessageType.
String resolveConversationPreview(ConversationSummary summary) {
  final preview = summary.lastMessagePreview;
  if (preview != null && preview.isNotEmpty) return preview;
  return switch (summary.lastMessageType) {
    MessageType.image => MessagingStrings.listPhoto,
    MessageType.video => MessagingStrings.listVideo,
    MessageType.voice => MessagingStrings.listVoice,
    _ => MessagingStrings.noMessagesYet,
  };
}

// Format a media duration as m:ss (e.g. 1:05, 0:07). A video timecode is NOT a
// count — it is a fixed clock format, so western digits and a zero-padded seconds
// field are used deliberately (formatCount would localise digits and drop the pad,
// producing "1:5"). A null/negative duration reads as 0:00 rather than throwing.
String formatMediaDuration(int? millis) {
  final ms = (millis ?? 0) < 0 ? 0 : (millis ?? 0);
  final totalSeconds = ms ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

// The displayed size of a media bubble, preserving the server-supplied aspect ratio
// and reserving space BEFORE the image loads so the list never reflows. Given the
// intrinsic width/height (nullable — a legacy/edge message may omit them) and a
// caller max box, returns the box to lay out. When dimensions are unknown a square
// fallback at maxWidth is used so there is still a stable reserved area.
class MediaBox {
  final double width;
  final double height;
  const MediaBox(this.width, this.height);
}

MediaBox resolveMediaBox({
  int? mediaWidth,
  int? mediaHeight,
  required double maxWidth,
  required double maxHeight,
}) {
  final w = (mediaWidth ?? 0).toDouble();
  final h = (mediaHeight ?? 0).toDouble();
  if (w <= 0 || h <= 0) {
    // Unknown aspect ratio → a stable square, capped to the max box.
    final side = maxWidth < maxHeight ? maxWidth : maxHeight;
    return MediaBox(side, side);
  }
  final aspect = w / h;
  // Fit within maxWidth first, then clamp height, preserving the ratio throughout.
  var outW = maxWidth;
  var outH = outW / aspect;
  if (outH > maxHeight) {
    outH = maxHeight;
    outW = outH * aspect;
  }
  return MediaBox(outW, outH);
}

// ── Voice notes (F-M11) ────────────────────────────────────────────────────────

// Composer control: an empty field shows the mic (record), any text shows send.
// Trivial, but it drives a visible control — a wrong branch means the user can't
// send text at all — so it is one explicit tested function, not an inline `if`.
enum ComposerAction { mic, send }

ComposerAction resolveComposerAction(String text) =>
    text.trim().isEmpty ? ComposerAction.mic : ComposerAction.send;

// Voice limits, MIRRORING the server (ChatService). Client fails fast; the server
// re-checks and is authoritative (duration especially — see below).
class VoiceLimits {
  VoiceLimits._();

  static const int maxBytes = 10 * 1024 * 1024; // 10 MB
  static const int maxDurationSeconds = 300; // 5 min — server auto-rejects beyond
  static const int maxDurationMs = maxDurationSeconds * 1000;

  // Waveform: at most 64 samples (server rejects more) and the column caps at 512
  // chars. Amplitude is sampled at this interval while recording, then downsampled.
  static const int maxWaveformSamples = 64;
  static const Duration sampleInterval = Duration(milliseconds: 100);

  // A recording shorter than this is treated as an accidental tap: discarded with a
  // "hold to record" hint rather than sent.
  static const int minDurationMs = 1000;
}

// Press-and-hold drag thresholds (logical pixels). Named, not magic numbers.
class RecordDragThresholds {
  RecordDragThresholds._();
  // Distance toward the START edge before the recording cancels.
  static const double cancel = 80;
  // Distance UPWARD before the recording locks (hands-free).
  static const double lock = 80;
}

// The outcome of the in-progress hold gesture. `none` while below both thresholds.
enum RecordDragOutcome { none, cancel, lock }

// Resolve the single outcome of a (possibly diagonal) hold-drag. Horizontal intent
// is expressed as "toward the start edge" so it mirrors correctly in RTL — a
// hardcoded left/right would invert the cancel gesture for Arabic/Urdu users.
//
// Diagonal resolution (the ambiguous case must yield EXACTLY one outcome): each
// axis is measured as a ratio of its own threshold; the axis further along wins.
// On a tie, LOCK wins deliberately — locking is non-destructive, whereas cancel
// discards the recording, so the safe outcome is preferred when intent is unclear.
RecordDragOutcome resolveRecordingDrag({
  required double dragX,
  required double dragY,
  required TextDirection direction,
  double cancelThreshold = RecordDragThresholds.cancel,
  double lockThreshold = RecordDragThresholds.lock,
}) {
  // Positive = toward the start edge (LTR: leftward/-dx; RTL: rightward/+dx).
  final startward = direction == TextDirection.ltr ? -dragX : dragX;
  final upward = -dragY; // positive = upward
  final canCancel = startward >= cancelThreshold;
  final canLock = upward >= lockThreshold;

  if (canCancel && canLock) {
    final cancelRatio = startward / cancelThreshold;
    final lockRatio = upward / lockThreshold;
    return lockRatio >= cancelRatio
        ? RecordDragOutcome.lock
        : RecordDragOutcome.cancel;
  }
  if (canLock) return RecordDragOutcome.lock;
  if (canCancel) return RecordDragOutcome.cancel;
  return RecordDragOutcome.none;
}

// Map a recorder amplitude reading (dBFS — 0 loudest, negative quieter) to a 0–100
// level for the waveform. Below the noise floor reads as 0; 0 dBFS reads as 100.
// A finite floor keeps quiet speech visible instead of collapsing to nothing.
int amplitudeToLevel(double dbfs, {double floor = -45.0}) {
  if (dbfs.isNaN || dbfs.isInfinite) return 0;
  if (dbfs >= 0) return 100;
  if (dbfs <= floor) return 0;
  return (((dbfs - floor) / (0 - floor)) * 100).round().clamp(0, 100);
}

// Downsample collected 0–100 samples to AT MOST maxSamples, as a comma-separated
// string for the wire. Buckets are averaged so the shape is preserved. Raw samples
// are never sent (the server rejects >64 and caps the column at 512 chars).
//
// Edge cases: an empty list → '' (the caller then sends NO waveform — null is valid
// and the bubble falls back to a flat bar); a single sample → that value; all-silent
// input → a valid string of zeros (never empty/malformed); far more than maxSamples
// → exactly maxSamples averaged buckets.
String downsampleWaveform(List<int> samples, {int maxSamples = 64}) {
  if (samples.isEmpty) return '';
  final clamped = [for (final s in samples) s.clamp(0, 100)];
  if (clamped.length <= maxSamples) return clamped.join(',');

  final n = clamped.length;
  final out = <int>[];
  for (var i = 0; i < maxSamples; i++) {
    final start = (i * n) ~/ maxSamples;
    final rawEnd = ((i + 1) * n) ~/ maxSamples;
    final end = rawEnd > start ? rawEnd : start + 1;
    var sum = 0;
    var count = 0;
    for (var j = start; j < end && j < n; j++) {
      sum += clamped[j];
      count++;
    }
    out.add(count == 0 ? 0 : (sum / count).round());
  }
  return out.join(',');
}

// Parse a server waveform string back into 0–100 levels for rendering. Null/empty →
// an empty list; the bubble draws a flat bar for that (never an error). Malformed
// entries are skipped defensively rather than throwing on a bad payload.
List<int> parseWaveform(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final out = <int>[];
  for (final part in raw.split(',')) {
    final v = int.tryParse(part.trim());
    if (v != null) out.add(v.clamp(0, 100));
  }
  return out;
}