import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/user_avatar.dart';
import '../../data/models/network_models.dart';

// ── Pure helpers — no BuildContext, no widget state, fully unit-testable ─────

class FollowSubtitleResult {
  final String text;
  // true only for "Followed by ..." — triggers the avatar stack in the UI
  final bool showAvatarStack;

  const FollowSubtitleResult({required this.text, required this.showAvatarStack});
}

// Comma-separates integers: 2100 → "2,100", 1000000 → "1,000,000"
String formatFollowersCount(int n) {
  final s = n.toString();
  if (s.length <= 3) return s;
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _socialProofText(List<SocialProofUser> preview) {
  if (preview.length == 1) {
    return 'Followed by ${preview[0].fullName}';
  }
  if (preview.length == 2) {
    // "and 1 others" would be wrong — use both names instead
    return 'Followed by ${preview[0].fullName} and ${preview[1].fullName}';
  }
  // 3+ items: "and N-1 others" is truthful because backend caps preview at 3,
  // meaning at least preview.length-1 people beyond the first name actually follow them.
  return 'Followed by ${preview[0].fullName} and ${preview.length - 1} others';
}

/// One subtitle line per card, priority-selected:
///   1. followedByPreview not empty  → social proof text + avatar stack flag
///   2. sharedSkills not empty       → first 2 skills joined by ", "
///   3. followersCount > 0           → "N,NNN followers" (thousands-formatted)
///   4. else                         → null (headline already shown above; no fallback noise)
FollowSubtitleResult? buildFollowSubtitle(
  List<SocialProofUser> followedByPreview,
  List<String> sharedSkills,
  int followersCount,
) {
  if (followedByPreview.isNotEmpty) {
    return FollowSubtitleResult(
      text: _socialProofText(followedByPreview),
      showAvatarStack: true,
    );
  }
  if (sharedSkills.isNotEmpty) {
    return FollowSubtitleResult(
      text: sharedSkills.take(2).join(', '),
      showAvatarStack: false,
    );
  }
  if (followersCount > 0) {
    return FollowSubtitleResult(
      text: '${formatFollowersCount(followersCount)} followers',
      showAvatarStack: false,
    );
  }
  return null;
}

// ── FollowSuggestionCard ───────────────────────────────────────────────────────
// Horizontal list-style card (vertical list, NOT the 2-column grid used for
// connect-suggestions). All loading state lives in FollowSuggestionsNotifier.
class FollowSuggestionCard extends StatelessWidget {
  const FollowSuggestionCard({
    super.key,
    required this.suggestion,
    required this.isFollowing,
    required this.isBusy,
    required this.onFollow,
    required this.onUnfollow,
    required this.onDismiss,
  });

  final FollowSuggestion suggestion;
  final bool isFollowing;
  final bool isBusy;
  final VoidCallback onFollow;
  final VoidCallback onUnfollow;
  final VoidCallback onDismiss;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    final subtitle = buildFollowSubtitle(
      suggestion.followedByPreview,
      suggestion.sharedSkills,
      suggestion.followersCount,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.08), width: 0.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar: 52×52 (radius 26). Slight top offset so it aligns with first text line.
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: UserAvatar(
              fullName: suggestion.fullName,
              photoUrl: suggestion.photoUrl,
              radius: 26,
            ),
          ),
          const SizedBox(width: 12),

          // Text content — Expanded so long names/headlines never escape card bounds
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // fullName: maxLines 1 — a 60-char name is truncated, not reflowed
                Text(
                  suggestion.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _navy,
                  ),
                ),

                // Headline: omit entirely when null/empty — no gap noise
                if (suggestion.headline != null &&
                    suggestion.headline!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    suggestion.headline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: _navy.withValues(alpha: 0.55),
                    ),
                  ),
                ],

                // Subtitle: null → nothing rendered, not even a gap
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  _SubtitleRow(
                    result: subtitle,
                    preview: suggestion.followedByPreview,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Right column: dismiss × at top, follow toggle below.
          // Embedded in the Row (not a Stack overlay) so their tap areas never conflict.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Dismiss — 44×44 tap target, visually subtle so it doesn't compete with Follow
              Semantics(
                label: 'Dismiss ${suggestion.fullName}',
                button: true,
                child: GestureDetector(
                  onTap: isBusy ? null : onDismiss,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: _navy.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Follow / Unfollow toggle — StadiumBorder pill, 44px tall for tap target
              SizedBox(
                height: 44,
                width: 100,
                child: OutlinedButton(
                  onPressed:
                      isBusy ? null : (isFollowing ? onUnfollow : onFollow),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isFollowing
                        ? _navy.withValues(alpha: 0.07)
                        : null,
                    foregroundColor: isFollowing
                        ? _navy.withValues(alpha: 0.5)
                        : _gold,
                    side: BorderSide(
                      color: isFollowing
                          ? _navy.withValues(alpha: 0.16)
                          : _gold,
                      width: 1.5,
                    ),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: isBusy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isFollowing
                                ? _navy.withValues(alpha: 0.5)
                                : _gold,
                          ),
                        )
                      : Text(
                          isFollowing ? 'Following' : '+ Follow',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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

// ── Subtitle row — optional avatar stack before the text ──────────────────────
class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({required this.result, required this.preview});

  final FollowSubtitleResult result;
  final List<SocialProofUser> preview;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    if (!result.showAvatarStack) {
      return Text(
        result.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: _navy.withValues(alpha: 0.55)),
      );
    }
    return Row(
      children: [
        _AvatarStack(preview: preview.take(3).toList()),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            result.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _navy.withValues(alpha: 0.55)),
          ),
        ),
      ],
    );
  }
}

// ── Overlapping proof-avatar stack ────────────────────────────────────────────
// Uses Positioned inside Stack — no negative margins as required.
// "Border in surface color": 1.5px white padding acts as the border ring.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.preview});

  final List<SocialProofUser> preview;

  static const _size = 18.0;
  static const _step = 11.0;

  @override
  Widget build(BuildContext context) {
    if (preview.isEmpty) return const SizedBox.shrink();
    final count = preview.length;
    final totalWidth = _size + (count - 1) * _step;

    return SizedBox(
      width: totalWidth,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Paint in reverse so index 0 (leftmost) renders on top
          for (var i = count - 1; i >= 0; i--)
            Positioned(
              left: i * _step,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white, // "border in surface color" via outer ring
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: UserAvatar(
                    fullName: preview[i].fullName,
                    photoUrl: preview[i].photoUrl,
                    radius: (_size - 3) / 2, // 7.5
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
