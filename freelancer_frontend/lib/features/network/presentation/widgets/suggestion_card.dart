import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/user_avatar.dart';
import '../../data/models/network_models.dart';

// ── Pure helper: reason chip text ─────────────────────────────────────────────
// No BuildContext, no widget state — fully unit-testable.
// Returns null when there is nothing meaningful to show (no mutual, no shared skills).
String? buildReasonChipText(int mutualCount, List<String> sharedSkills) {
  final hasMutual = mutualCount > 0;
  final hasSkills = sharedSkills.isNotEmpty;

  if (!hasMutual && !hasSkills) return null;

  if (hasMutual && hasSkills) {
    final m = mutualCount == 1 ? '1 mutual' : '$mutualCount mutual';
    final s = sharedSkills.take(2).join(', ');
    return '$m · $s';
  }

  if (hasMutual) {
    return mutualCount == 1
        ? '1 mutual connection'
        : '$mutualCount mutual connections';
  }

  // hasSkills only
  return sharedSkills.take(2).join(', ');
}

// ── Pure helper: deterministic cover tint ─────────────────────────────────────
// Picks from palette-derived muted tints so the same person always gets the
// same color without storing any state. Tints are intentionally de-saturated
// versions of the navy+gold design system palette — they feel on-brand without
// competing with the avatar or card text.
Color suggestionCoverTint(String userId) {
  const tints = [
    Color(0xFFE8EBF3), // muted navy tint
    Color(0xFFF5EFDF), // muted gold tint
    Color(0xFFE5EDF8), // blue-navy tint
    Color(0xFFF0EBE3), // warm sand
    Color(0xFFEAF0EA), // sage green
    Color(0xFFF3E8EF), // soft mauve
  ];
  return tints[userId.hashCode.abs() % tints.length];
}

// ── SuggestionCard ─────────────────────────────────────────────────────────────
// Stateless and callback-driven — all loading state lives in SuggestionsNotifier.
// The home section and full screen both render this exact widget.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.isRequested,
    required this.isBusy,
    required this.onConnect,
    required this.onDismiss,
  });

  final Suggestion suggestion;
  final bool isRequested;
  final bool isBusy;
  final VoidCallback onConnect;
  final VoidCallback onDismiss;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    final chipText = buildReasonChipText(
      suggestion.mutualConnectionsCount,
      suggestion.sharedSkills,
    );
    final tint = suggestionCoverTint(suggestion.userId);

    return Container(
      // clipBehavior: Clip.antiAlias clips children to the BorderRadius, which
      // is necessary so the cover strip has rounded top corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.08), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Cover strip + avatar ─────────────────────────────────────────
          // Stack height: 52 (cover) + 30 (avatar extension below cover) = 82.
          // Avatar (60×60 including 2px white border) starts at top: 26,
          // so 26px of the avatar overlaps into the cover strip.
          // clipBehavior: Clip.none lets the remaining 4px extend below the
          // SizedBox into the Expanded padding area — no layout jump occurs
          // because the Padding's 8px top gap absorbs it.
          SizedBox(
            height: 82,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Cover strip
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(height: 52, color: tint),
                ),

                // Dismiss: 44×44 tap area, 26×26 visual circle
                Positioned(
                  top: 4,
                  right: 4,
                  child: Semantics(
                    label: 'Dismiss ${suggestion.fullName}',
                    button: true,
                    child: GestureDetector(
                      onTap: isBusy ? null : onDismiss,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.85),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: _navy.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Avatar — white ring (2px Padding) around 56×56 UserAvatar
                Positioned(
                  top: 26,
                  left: 12,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: UserAvatar(
                        fullName: suggestion.fullName,
                        photoUrl: suggestion.photoUrl,
                        radius: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Text content + connect button ────────────────────────────────
          // Expanded fills the remaining cell height (childAspectRatio determines
          // total cell height; Spacer below chip pushes the button to the bottom).
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // fullName: maxLines 2 — 60-char names must not overflow the card
                  Text(
                    suggestion.fullName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _navy,
                    ),
                  ),

                  // Headline: omitted entirely when null or empty (no gap noise)
                  if (suggestion.headline != null &&
                      suggestion.headline!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      suggestion.headline!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.55),
                      ),
                    ),
                  ],

                  // Reason chip: null → nothing rendered (not even a gap)
                  if (chipText != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        chipText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _gold.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Connect button
                  SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: OutlinedButton(
                      onPressed: (isRequested || isBusy) ? null : onConnect,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isRequested
                            ? _navy.withValues(alpha: 0.4)
                            : _gold,
                        side: BorderSide(
                          color: isRequested
                              ? _navy.withValues(alpha: 0.2)
                              : _gold,
                          width: 1.5,
                        ),
                        shape: const StadiumBorder(),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: isBusy
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _gold,
                              ),
                            )
                          : Text(
                              isRequested ? 'Pending' : 'Connect',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
