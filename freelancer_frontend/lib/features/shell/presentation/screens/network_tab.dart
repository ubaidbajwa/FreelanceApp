import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Network tab landing — existing connections screens push hote hain (full screen).
// Connections screens mein khud apna AppBar hota hai, isliye shell ke upar push hain.

class NetworkTab extends StatelessWidget {
  const NetworkTab({super.key});

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 88),
      children: [
        const Text(
          'MY NETWORK',
          style: TextStyle(
            color: _gold,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 3.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Manage your\nconnections',
          style: TextStyle(
            color: _navy,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 28),
        _NetworkEntry(
          icon: Icons.people_outline,
          label: 'People you may know',
          sublabel: 'Discover and connect with talent',
          onTap: () => context.push('/people'),
        ),
        const SizedBox(height: 12),
        _NetworkEntry(
          icon: Icons.mail_outline,
          label: 'Invitations',
          sublabel: 'Received and sent connection requests',
          onTap: () => context.push('/connections/invitations'),
        ),
        const SizedBox(height: 12),
        _NetworkEntry(
          icon: Icons.link,
          label: 'My Connections',
          sublabel: 'Browse and search your connections',
          onTap: () => context.push('/connections'),
        ),
      ],
    );
  }
}

class _NetworkEntry extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  static const _navy = Color(0xFF0A1633);

  const _NetworkEntry({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: _navy, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sublabel,
                        style: TextStyle(
                          color: _navy.withValues(alpha: 0.55),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: _navy.withValues(alpha: 0.35)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
