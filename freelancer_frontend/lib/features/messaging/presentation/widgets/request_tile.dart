import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/user_avatar.dart';
import '../../../../core/utils/relative_time.dart';
import '../../data/models/messaging_models.dart';
import '../../messaging_strings.dart';

// Incoming message-request ki row: conversation tile jaisa upar wala hissa +
// Accept (gold pill) / Decline (muted) buttons. Busy hone pe dono buttons ki
// jagah ek spinner (dono disabled). Fail SnackBar caller (screen) dikhata hai.
class RequestTile extends StatelessWidget {
  const RequestTile({
    super.key,
    required this.summary,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final ConversationSummary summary;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    final preview = summary.lastMessagePreview ?? MessagingStrings.noMessagesYet;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.08), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: 13,
                        color: _navy.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              // Timestamp null pe helper '' deta hai (koi `!`); row height avatar
              // se driven hai, khali string se shift/overflow nahi.
              const SizedBox(width: 8),
              Text(
                formatRelativeTimestamp(summary.lastMessageAt),
                style: TextStyle(
                  fontSize: 11,
                  color: _navy.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Busy pe spinner (buttons ki fixed height jitni) — card resize na ho
          if (busy)
            const SizedBox(
              height: 40,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                ),
              ),
            )
          else
            Row(
              children: [
                // Decline — muted outlined pill
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      onPressed: onDecline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: BorderSide(color: _navy.withValues(alpha: 0.30)),
                        shape: const StadiumBorder(),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        MessagingStrings.decline,
                        style:
                            TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Accept — navy fill (design-system primary action, CLAUDE.md:
                // "navy fill, StadiumBorder pills; gold never used as button
                // fill"). Slice ka "gold pill" wording galat tha — project-wide
                // design system slice-level instruction se override nahi hota.
                // Same treatment jaisa my_connections "Discover People" FilledButton.
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: FilledButton(
                      onPressed: onAccept,
                      style: FilledButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        MessagingStrings.accept,
                        style:
                            TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
