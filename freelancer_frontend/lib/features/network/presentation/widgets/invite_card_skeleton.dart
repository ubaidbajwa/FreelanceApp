import 'package:flutter/material.dart';

// Hand-rolled shimmer shaped like one invite card — same technique as
// NetworkOverviewSkeleton (AnimationController, no extra package).
class InviteCardSkeleton extends StatefulWidget {
  const InviteCardSkeleton({super.key});

  @override
  State<InviteCardSkeleton> createState() => _InviteCardSkeletonState();
}

class _InviteCardSkeletonState extends State<InviteCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF0A1633).withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // Avatar placeholder
              Container(
                width: 56,
                height: 56,
                decoration:
                    BoxDecoration(color: shimmer, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              // Text placeholders
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 15,
                      width: 130,
                      decoration: BoxDecoration(
                        color: shimmer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 13,
                      decoration: BoxDecoration(
                        color: shimmer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
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
              // Button placeholders (two stacked circles)
              Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration:
                        BoxDecoration(color: shimmer, shape: BoxShape.circle),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 40,
                    decoration:
                        BoxDecoration(color: shimmer, shape: BoxShape.circle),
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
