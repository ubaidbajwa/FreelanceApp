// Har user-visible string is slice ka yahin hai — widgets mein koi literal nahi.
// Global-audience req #4: single file per feature taake baad ki ARB extraction
// mechanical rahe (abhi ARB / codegen set up NAHI kar rahe — sirf seam).
import '../../core/utils/number_format.dart';

class MessagingStrings {
  MessagingStrings._();

  // Tab / header
  static const overline = 'MESSAGES';
  static const tabMessages = 'Messages';
  static const tabRequests = 'Requests';

  // Conversation tile
  // Defensive fallback — backend preview-less threads filter kar deta hai, lekin
  // agar aa jaye to crash na ho.
  static const noMessagesYet = 'No messages yet';

  // Unread badge overflow cap. Raw 4-digit count tile layout tod deta hai, is
  // liye 99 se upar cap hota hai. Numeric hissa (99) phir bhi formatCount se
  // localize hota hai; sirf suffix literal yahan token ban kar rehta hai.
  // Baad ki screens isi threshold + token ko reuse karein (dobara decide na karein).
  static const unreadCountCap = 99;
  static const unreadCountOverflowSuffix = '+';

  // Empty states (accepted vs requests — alag messages)
  static const emptyConversationsTitle = 'No conversations yet';
  static const emptyConversationsBody =
      'Your chats with clients and\nfreelancers will appear here.';
  static const emptyRequestsTitle = 'No message requests';
  static const emptyRequestsBody =
      'When someone new messages you,\ntheir request shows up here.';

  // Request actions
  static const accept = 'Accept';
  static const decline = 'Decline';

  // Load-more failure (inline retry at list bottom)
  static const loadMoreFailed = "Couldn't load more.";
  static const retry = 'Retry';

  // Generic fallback jab backend ProblemDetails detail na de
  static const genericError = 'Something went wrong. Try again.';

  // ── Chat screen (F-M2) ────────────────────────────────────────────────────
  // Day separators — labels core relative_time helper mein inject hote hain.
  static const chatToday = 'Today';
  static const chatYesterday = 'Yesterday';

  // Composer
  static const composerHint = 'Message';
  // Character limit (backend MaximumLength(4000)) + counter kab dikhe.
  static const messageCharLimit = 4000;
  static const messageCharCounterThreshold = 3600; // remaining <= 400 pe counter

  // Empty accepted thread
  static const chatEmpty = 'No messages yet.';

  // State B — pending, viewer initiator hai (apna ek allowed message bhej chuka)
  static const stateBWaiting =
      'Request sent. You can message again once it\'s accepted.';

  // State D — declined (read-only)
  static const stateDeclined = 'This message request was declined.';

  // Unknown/degraded — summary bina cold-open (koi status maloom nahi)
  static const chatUnavailable =
      'Couldn\'t load this conversation. Open it from your Messages list.';

  // Failed send bubble affordance
  static const sendFailedRetry = 'Failed — tap to retry';

  // Non-text message type placeholder (sirf Text ban sakta hai M1 mein)
  static const unsupportedMessage = 'Unsupported message';

  // Cold-open access errors — shown as read-only infoStrip (not retryable full-screen error)
  static const chat403NotParticipant =
      'You\'re no longer part of this conversation.';
  static const chat404NotFound = 'This conversation no longer exists.';

  // Conversation tile — outgoing pending request (status==pending && isRequest==false)
  static const requestSentLabel = 'Request sent';

  // Placeholder chat screen (F-M2 asli screen banayega)
  static const chatComingSoon = 'Chat coming next';

  // ── Selection mode + message actions (F-M4) ────────────────────────────────

  // Backend pins ki cap (M3: 3 → 4). Sirf UI affordance — server authoritative.
  // M3 mein cap par 409 ab generic error nahi: replace-oldest dialog trigger karta
  // hai (pinReplace* neeche). pinLimitReached ab last-resort fallback string hai.
  static const pinnedMax = 4;
  static String pinLimitReached() =>
      'You can pin up to ${formatCount(pinnedMax)} messages.';

  // Toolbar tooltips + selection app-bar semantic labels
  static const actionCopy = 'Copy';
  static const actionDelete = 'Delete';
  static const actionPin = 'Pin';
  static const actionUnpin = 'Unpin';
  static const selectionCancel = 'Cancel selection';
  static const copied = 'Copied';

  // Tombstone (delete-for-everyone) — muted italic, not selectable.
  static const messageDeleted = 'This message was deleted';

  // Delete dialog — title count reflect karta hai (ek vs kai). Count formatCount se.
  static String deleteDialogTitle(int count) => count == 1
      ? 'Delete message?'
      : 'Delete ${formatCount(count)} messages?';
  static const deleteForEveryone = 'Delete for everyone';
  static const deleteForMe = 'Delete for me';
  static const cancel = 'Cancel';

  // Partial-failure snackbar jab kuch messages delete na ho payein.
  static String deletePartialFailure(int failed) => failed == 1
      ? "Couldn't delete ${formatCount(1)} message."
      : "Couldn't delete ${formatCount(failed)} messages.";

  // ── Reply (F-M5) ─────────────────────────────────────────────────────────────
  static const actionReply = 'Reply';
  static const replyYou = 'You';
  static const replyPhoto = 'Photo';
  static const replyFile = 'File';
  static const replyVoice = 'Voice message';
  static const replyDeletedQuote = 'Original message deleted';
  static const replyOriginalNotLoaded =
      'The original message is further back in the conversation.';

  // ── Forward (F-M6) ────────────────────────────────────────────────────────────
  static const actionForward = 'Forward';
  // Inside bubble — low visual weight, metadata not content.
  static const forwardedLabel = 'Forwarded';
  static const forwardPickerTitle = 'Forward to';
  static const forwardSearchHint = 'Search conversations';
  static String forwardingCount(int n) => n == 1
      ? 'Forwarding ${formatCount(1)} message'
      : 'Forwarding ${formatCount(n)} messages';
  static const forwardSuccess = 'Message forwarded';
  static const forwardNoConversations = 'No conversations to forward to';
  static const forwardNoResults = 'No conversations match your search';

  // ── Pin banner (F-M6) ─────────────────────────────────────────────────────────
  static const pinBannerTitle = 'Pinned Message';
  // "1 of 3" cycle indicator — only shown when there is more than one pin.
  static String pinBannerOf(int current, int total) =>
      '${formatCount(current)} of ${formatCount(total)}';
  static const pinBannerUnpinTooltip = 'Unpin message';

  // ── Edit (F-M6) ──────────────────────────────────────────────────────────────
  static const actionEdit = 'Edit';
  static const editBannerLabel = 'Editing message';
  // Muted marker shown next to the timestamp when editedAt is non-null.
  static const editedMarker = 'edited';
  // 403 response: window elapsed while user was composing their edit.
  static const editWindowExpired =
      'The edit window has passed. Your text is preserved — '
      'you can copy it or send it as a new message.';

  // ── Pin duration dialog (M3) ─────────────────────────────────────────────────
  // Pin se pehle: kitni der pin rahe. Ek option hamesha selected (24h default),
  // is liye confirm button kabhi disabled nahi hota.
  static const pinDurationTitle = 'How long should this pin last?';
  static const pinDurationSubtitle = 'You can unpin it at any time.';
  static const pinDuration24h = '24 hours';
  static const pinDuration7d = '7 days';
  static const pinDuration30d = '30 days';
  static const pinConfirm = 'Pin';

  // ── Replace-oldest dialog (M3) ───────────────────────────────────────────────
  // Cap (4) par 409 aane par — error nahi, yeh confirm dikhta hai. Continue wahi
  // duration ke sath replaceOldest:true bhejta hai (user dobara nahi chunta).
  static const pinReplaceTitle = 'Replace the oldest pin?';
  static const pinReplaceSubtitle =
      'You already have the maximum number of pinned messages. '
      'The new pin will replace the oldest one.';
  static const pinReplaceContinue = 'Continue';

  // ── System messages (M3) ─────────────────────────────────────────────────────
  // body hamesha khali aati hai — sentence yahan banti hai (per-viewer + baad mein
  // translatable). "You" jab caller khud actor ho, warna doosre ka naam.
  static const systemYouPinned = 'You pinned a message';
  static const systemYouUnpinned = 'You unpinned a message';
  static String systemOtherPinned(String name) => '$name pinned a message';
  static String systemOtherUnpinned(String name) => '$name unpinned a message';
}
