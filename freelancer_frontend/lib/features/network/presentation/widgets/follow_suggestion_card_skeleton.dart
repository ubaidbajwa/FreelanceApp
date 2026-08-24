import 'package:flutter/material.dart';

// Hand-rolled shimmer matching FollowSuggestionCard's horizontal layout.
// Same technique as SuggestionCardSkeleton — AnimationController, no external package.
class FollowSuggestionCardSkeleton extends StatefulWidget {
  const FollowSuggestionCardSkeleton({super.key});

  @override
  State<FollowSuggestionCardSkeleton> createState() =>
      _FollowSuggestionCardSkeletonState();
}

class _FollowSuggestionCardSkeletonState
    extends State<FollowSuggestionCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  static const _navy = Color(0xFF0A1633);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) {
        final shimmer = Color.lerp(
          const Color(0xFFE0E0E0),
          const Color(0xFFF0F0F0),
          _fade.value,
        )!;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _navy.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar circle
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: shimmer,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Text placeholders
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    // Name
                    Container(
                      height: 14,
                      width: 120,
                      decoration: BoxDecoration(
                        color: shimmer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Headline
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: shimmer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Subtitle (shorter)
                    Container(
                      height: 12,
                      width: 100,
                      decoration: BoxDecoration(
                        color: shimmer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Right column: dismiss placeholder + button placeholder
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Dismiss × placeholder
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: shimmer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Follow button placeholder
                  Container(
                    width: 100,
                    height: 44,
                    decoration: BoxDecoration(
                      color: shimmer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
