import 'package:flutter/material.dart';

// Hand-rolled shimmer — no extra package needed.
// Shaped like the STATE B stats card (the more common post-onboarding state).
class NetworkOverviewSkeleton extends StatefulWidget {
  const NetworkOverviewSkeleton({super.key});

  @override
  State<NetworkOverviewSkeleton> createState() =>
      _NetworkOverviewSkeletonState();
}

class _NetworkOverviewSkeletonState extends State<NetworkOverviewSkeleton>
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
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF0A1633).withValues(alpha: 0.08),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 140,
                height: 16,
                decoration: BoxDecoration(
                  color: shimmer,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: List.generate(
                  3,
                  (i) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 12.0 : 0),
                      child: Column(
                        children: [
                          Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: shimmer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 13,
                            decoration: BoxDecoration(
                              color: shimmer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
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
