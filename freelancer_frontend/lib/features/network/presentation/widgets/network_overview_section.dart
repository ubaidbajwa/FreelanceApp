import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/network_overview_notifier.dart';
import '../../data/models/network_models.dart';
import 'network_overview_skeleton.dart';

class NetworkOverviewSection extends ConsumerWidget {
  const NetworkOverviewSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(networkOverviewProvider);

    if (state.loading) return const NetworkOverviewSkeleton();

    if (state.error != null) {
      return _ErrorCard(
        onRetry: () => ref.read(networkOverviewProvider.notifier).refresh(),
      );
    }

    final overview = state.overview;
    if (overview == null) return const SizedBox.shrink();

    return overview.connectionsCount == 0
        ? _BuildYourNetworkCard(overview: overview)
        : _NetworkStatsCard(overview: overview);
  }
}

// ── Error ──────────────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final VoidCallback onRetry;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: _navy.withValues(alpha: 0.5), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Could not load network overview.',
              style: TextStyle(fontSize: 14, color: _navy.withValues(alpha: 0.65)),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(color: _navy)),
          ),
        ],
      ),
    );
  }
}

// ── STATE A — connectionsCount == 0 ──────────────────────────────────────────

class _BuildYourNetworkCard extends StatelessWidget {
  const _BuildYourNetworkCard({required this.overview});
  final NetworkOverview overview;

  static const _navy = Color(0xFF0A1633);
  static const _ivory = Color(0xFFFAFAF8);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.10)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Build your network',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Clients notice strong networks. Start with 5 people you know.',
            style: TextStyle(
              fontSize: 14,
              color: _navy.withValues(alpha: 0.55),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _ConnectionCirclesRow(connectionsCount: overview.connectionsCount),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push('/people'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: _ivory,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Find people you know',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCirclesRow extends StatelessWidget {
  const _ConnectionCirclesRow({required this.connectionsCount});
  final int connectionsCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (i) {
        return i < connectionsCount
            ? const _FilledCircle()
            : _DashedCircle(number: i + 1);
      }),
    );
  }
}

class _FilledCircle extends StatelessWidget {
  const _FilledCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFF0A1633),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, color: Colors.white, size: 22),
    );
  }
}

class _DashedCircle extends StatelessWidget {
  const _DashedCircle({required this.number});
  final int number;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: CustomPaint(
        painter: _DashedCirclePainter(
          color: _navy.withValues(alpha: 0.25),
          strokeWidth: 1.5,
        ),
        child: Center(
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _navy.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color, required this.strokeWidth});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    const dashCount = 14;
    const dashFraction = 0.55;
    const step = (2 * math.pi) / dashCount;
    const sweep = step * dashFraction;

    for (var i = 0; i < dashCount; i++) {
      final startAngle = i * step - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

// ── STATE B — connectionsCount > 0 ───────────────────────────────────────────

class _NetworkStatsCard extends StatelessWidget {
  const _NetworkStatsCard({required this.overview});
  final NetworkOverview overview;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Network overview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
              const Spacer(),
              // TODO: navigate to full network overview page in a later slice
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: _navy.withValues(alpha: 0.4),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // invitesSentCount and invitesReceivedCount are intentionally excluded here.
          // Stats show reach (Connections, Followers, Following = identity/reach);
          // invite counts are actionable work that belongs in the Invites section above.
          Row(
            children: [
              _StatItem(label: 'Connections', value: overview.connectionsCount),
              _StatItem(label: 'Followers', value: overview.followersCount),
              _StatItem(label: 'Following', value: overview.followingCount),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final int value;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: _navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: _navy.withValues(alpha: 0.55)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
