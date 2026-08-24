// "Who can connect with you" — single flat screen with 3 radio cards.
//
// WHY flat (not nested toggles): Skillora has exactly one enforceable invite
// control. LinkedIn-style sub-sections (everyone / connections of connections /
// etc.) would create false affordances — we only build controls we can actually
// enforce on the backend. Three options, one PUT, no confusion.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/profile/data/models/profile_model.dart';
import '../../application/invite_policy_notifier.dart';

class ConnectionPrivacyScreen extends ConsumerWidget {
  const ConnectionPrivacyScreen({super.key});

  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);

  // Static helper so context.mounted check works correctly after async gap.
  static Future<void> _select(
    BuildContext ctx,
    WidgetRef ref,
    ConnectionInvitePolicy p,
  ) async {
    final err = await ref.read(invitePolicyProvider.notifier).setPolicy(p);
    if (!ctx.mounted || err == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(err), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(invitePolicyProvider);

    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(
        backgroundColor: _ivory,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _navy,
        title: const Text(
          'Who can connect with you',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _navy,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: _navy,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: state.loading
          ? _loadingView()
          : state.error != null
              ? _errorView(state.error!, ref)
              : _contentView(context, ref, state),
    );
  }

  // ── Loading — 3 card skeletons ─────────────────────────────────────────────

  Widget _loadingView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subtitle placeholder
          const _Shimmer(width: 240, height: 14, radius: 4),
          const SizedBox(height: 28),
          const _PolicyCardSkeleton(),
          const SizedBox(height: 12),
          const _PolicyCardSkeleton(),
          const SizedBox(height: 12),
          const _PolicyCardSkeleton(),
        ],
      ),
    );
  }

  // ── Error — inline retry, not full-screen alert ────────────────────────────

  Widget _errorView(String message, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: _navy.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, color: _navy.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => ref.read(invitePolicyProvider.notifier).retry(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: BorderSide(color: _navy.withValues(alpha: 0.35)),
                shape: const StadiumBorder(),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Content — 3 selectable radio cards ────────────────────────────────────

  Widget _contentView(
      BuildContext context, WidgetRef ref, InvitePolicyState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Control who can send you a connection invitation.',
            style: TextStyle(
              fontSize: 14,
              color: _navy.withValues(alpha: 0.55),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          _PolicyCard(
            label: 'Everyone',
            subtitle: 'Anyone on Skillora can send you an invite',
            policy: ConnectionInvitePolicy.everyone,
            selected: state.policy == ConnectionInvitePolicy.everyone,
            saving: state.saving,
            onTap: () => _select(context, ref, ConnectionInvitePolicy.everyone),
          ),
          const SizedBox(height: 12),
          _PolicyCard(
            label: 'People I share a connection with',
            subtitle: 'Only mutual connections can invite you',
            policy: ConnectionInvitePolicy.mutualsOnly,
            selected: state.policy == ConnectionInvitePolicy.mutualsOnly,
            saving: state.saving,
            onTap: () =>
                _select(context, ref, ConnectionInvitePolicy.mutualsOnly),
          ),
          const SizedBox(height: 12),
          _PolicyCard(
            label: 'No one',
            subtitle: 'Turn off all connection invitations',
            policy: ConnectionInvitePolicy.noOne,
            selected: state.policy == ConnectionInvitePolicy.noOne,
            saving: state.saving,
            onTap: () => _select(context, ref, ConnectionInvitePolicy.noOne),
          ),
        ],
      ),
    );
  }
}

// ── Selectable radio card ──────────────────────────────────────────────────────
// Visual match to onboarding selectable cards (_AvailabilityCard pattern):
//   selected  = navy bg + gold 1.5px border + filled gold radio dot
//   unselected = white bg + faint gold border (45% alpha, 1px) + hollow radio

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    required this.label,
    required this.subtitle,
    required this.policy,
    required this.selected,
    required this.saving,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final ConnectionInvitePolicy policy;
  final bool selected;
  final bool saving; // true = a save is in flight (any card)
  final VoidCallback onTap;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, ${selected ? "selected" : "not selected"}',
      child: GestureDetector(
        // notifier guards concurrent saves; we only tap-block for same-policy
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: selected ? _navy : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _gold : _gold.withValues(alpha: 0.45),
              width: selected ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Radio indicator: outer ring + inner filled dot when selected
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? _gold : _navy.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _gold,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : _navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? Colors.white.withValues(alpha: 0.65)
                            : _navy.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              // Saving spinner only on the selected (optimistically updated) card
              if (saving && selected)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _gold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card shimmer skeleton ──────────────────────────────────────────────────────
// Hand-rolled shimmer (no external package) — same pattern as InviteCardSkeleton.

class _PolicyCardSkeleton extends StatefulWidget {
  const _PolicyCardSkeleton();

  @override
  State<_PolicyCardSkeleton> createState() => _PolicyCardSkeletonState();
}

class _PolicyCardSkeletonState extends State<_PolicyCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final color = Color.lerp(
          const Color(0xFFE0E0E0),
          const Color(0xFFF0F0F0),
          _ctrl.value,
        )!;
        return Container(
          height: 76,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }
}

// ── Generic shimmer block (subtitle placeholder) ───────────────────────────────

class _Shimmer extends StatefulWidget {
  const _Shimmer({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final color = Color.lerp(
          const Color(0xFFE0E0E0),
          const Color(0xFFF0F0F0),
          _ctrl.value,
        )!;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}
