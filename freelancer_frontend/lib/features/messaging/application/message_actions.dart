// Pure decision logic for selection-mode actions. Kept OUT of the widget tree
// on purpose (spec): which toolbar icons show, and which delete-dialog options
// apply, is the conditional core of this slice — one explicit tested function
// each, not scattered ifs.

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