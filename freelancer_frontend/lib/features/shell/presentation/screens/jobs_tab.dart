import 'package:flutter/material.dart';

// TODO: jobs module

class JobsTab extends StatelessWidget {
  const JobsTab({super.key});

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.work_outline, size: 56, color: _navy.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          const Text(
            'Jobs',
            style: TextStyle(
              color: _navy,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Browse and apply to jobs\nfrom verified clients.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _navy.withValues(alpha: 0.5), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 20),
          Text(
            '// TODO: jobs module',
            style: TextStyle(
              color: _gold.withValues(alpha: 0.6),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
