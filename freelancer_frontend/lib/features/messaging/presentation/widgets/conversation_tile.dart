import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/user_avatar.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/relative_time.dart';
import '../../application/message_actions.dart';
import '../../data/models/messaging_models.dart';
import '../../messaging_strings.dart';

// Accepted conversation ki ek row. Unread hone pe name + preview heavier weight
// (standard unread affordance). Timestamp .toLocal() render-time pe lagta hai —
// formatRelativeTimestamp andar se karta hai (global-audience req #1).
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.summary,
    required this.onTap,
  });

  final ConversationSummary summary;
  final VoidCallback onTap;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    final unread = summary.unreadCount > 0;
    // F-M5: caption/text wins; an uncaptioned photo/video resolves to a localised
    // "Photo"/"Video" (pure fn), with a small leading icon added below.
    final preview = resolveConversationPreview(summary);
    // Show the icon ONLY when the preview IS the media label (no caption/text) —
    // a captioned media message reads as its caption, no icon.
    final showMediaIcon = (summary.lastMessagePreview == null ||
            summary.lastMessagePreview!.isEmpty) &&
        (summary.lastMessageType == MessageType.image ||
            summary.lastMessageType == MessageType.video ||
            summary.lastMessageType == MessageType.voice ||
            summary.lastMessageType == MessageType.file); // F-M8 document
    final mediaIcon = switch (summary.lastMessageType) {
      MessageType.video => Icons.videocam_rounded,
      MessageType.voice => Icons.mic_rounded,
      MessageType.file => Icons.description_rounded, // F-M8 document
      _ => Icons.photo_rounded,
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _navy.withValues(alpha: 0.08), width: 0.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              UserAvatar(
                fullName: summary.otherUser.fullName,
                photoUrl: summary.otherUser.photoUrl,
                radius: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      summary.otherUser.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: 15,
                        color: _navy,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (showMediaIcon) ...[
                          Icon(
                            mediaIcon,
                            size: 14,
                            color:
                                unread ? _navy : _navy.withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontSize: 13,
                              color: unread
                                  ? _navy
                                  : _navy.withValues(alpha: 0.55),
                              fontWeight:
                                  unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Trailing: timestamp (upar) + unread badge (neeche).
              // Timestamp null pe helper '' deta hai (koi `!` nahi). Row/column
              // ki height avatar (52px) se driven hai, is liye khali string se
              // koi shift ya overflow nahi hota.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatRelativeTimestamp(summary.lastMessageAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: _navy.withValues(alpha: unread ? 0.75 : 0.45),
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(height: 6),
                    _UnreadBadge(count: summary.unreadCount),
                  ] else if (summary.status == ConversationStatus.pending &&
                      !summary.isRequest) ...[
                    const SizedBox(height: 4),
                    Text(
                      MessagingStrings.requestSentLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Navy pill, gold count — avatar (navy bg + gold initials) wali brand pairing.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  // >99 pe cap (raw 4-digit count tile layout tod deta). Numeric hissa phir bhi
  // formatCount se localize hota hai; suffix strings-file token se aata hai.
  String get _display => count > MessagingStrings.unreadCountCap
      ? '${formatCount(MessagingStrings.unreadCountCap)}'
          '${MessagingStrings.unreadCountOverflowSuffix}'
      : formatCount(count);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _display,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _gold,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
