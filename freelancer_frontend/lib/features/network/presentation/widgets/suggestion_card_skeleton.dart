import 'package:flutter/material.dart';

// Hand-rolled shimmer shaped like one SuggestionCard — same technique as
// InviteCardSkeleton (AnimationController, no extra package needed).
class SuggestionCardSkeleton extends StatefulWidget {
  const SuggestionCardSkeleton({super.key});

  @override
  State<SuggestionCardSkeleton> createState() =>
      _SuggestionCardSkeletonState();
}

class _SuggestionCardSkeletonState extends State<SuggestionCardSkeleton>
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
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _navy.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cover + avatar area (same 82px as real card)
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
                      child: Container(height: 52, color: shimmer),
                    ),
                    // Avatar circle
                    Positioned(
                      top: 26,
                      left: 12,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: shimmer,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Text + button placeholders
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name line
                      Container(
                        height: 14,
                        width: 100,
                        decoration: BoxDecoration(
                          color: shimmer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Headline line 1
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: shimmer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Headline line 2 (shorter)
                      Container(
                        height: 12,
                        width: 80,
                        decoration: BoxDecoration(
                          color: shimmer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Chip placeholder
                      Container(
                        height: 22,
                        width: 90,
                        decoration: BoxDecoration(
                          color: shimmer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const Spacer(),
                      // Button placeholder
                      Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: shimmer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
