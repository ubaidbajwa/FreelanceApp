import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../application/profile_summary_notifier.dart';

// Role-aware More tab — freelancer aur client ke liye alag list items.

class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileSummaryProvider);
    final isClient = profile.role == 1;
    final items = isClient ? _clientItems : _freelancerItems;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 88),
      children: [
        const Text(
          'MORE',
          style: TextStyle(
            color: _gold,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 3.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isClient ? 'Manage your work' : 'Grow your career',
          style: const TextStyle(
            color: _navy,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 28),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MoreTile(icon: item.$1, label: item.$2),
          ),
        ),
        // ── Privacy settings ──────────────────────────────────────────────────
        const SizedBox(height: 8),
        const Text(
          'PRIVACY',
          style: TextStyle(
            color: _gold,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 3.5,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _MoreTile(
            icon: Icons.people_outline,
            label: 'Who can connect with you',
            onTap: () => context.push('/connection-privacy'),
          ),
        ),
      ],
    );
  }
}

// (icon, label) tuples — existing items, navigation is TODO per module
const _freelancerItems = [
  (Icons.description_outlined, 'My Applications'),
  (Icons.folder_open_outlined, 'Active Projects'),
  (Icons.account_balance_wallet_outlined, 'Payments'),
  (Icons.bar_chart_outlined, 'Growth Dashboard'),
  (Icons.settings_outlined, 'Settings'),
];

const _clientItems = [
  (Icons.post_add_outlined, 'Posted Jobs'),
  (Icons.inbox_outlined, 'Applications Received'),
  (Icons.folder_open_outlined, 'Projects'),
  (Icons.account_balance_wallet_outlined, 'Payments'),
  (Icons.settings_outlined, 'Settings'),
];

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  static const _navy = Color(0xFF0A1633);

  const _MoreTile({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap ?? () {
            // TODO: individual module routes
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: _navy, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: _navy.withValues(alpha: 0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
