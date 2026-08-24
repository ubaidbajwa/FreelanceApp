import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/network_overview_notifier.dart';
import '../widgets/invites_received_section.dart';
import '../widgets/network_overview_section.dart';
import '../widgets/suggestions_section.dart';
import '../widgets/follow_suggestions_section.dart';

class MyNetworkHomeScreen extends ConsumerWidget {
  const MyNetworkHomeScreen({super.key});

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: _navy,
      onRefresh: () => ref.read(networkOverviewProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            // Page header
            Text(
              'MY NETWORK',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _gold,
                letterSpacing: 3.5,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Your\nconnections',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: _navy,
                height: 1.12,
              ),
            ),
            SizedBox(height: 24),

            // 1. Invites received — fully built (F-N2)
            InvitesReceivedSection(),
            SizedBox(height: 12),

            // 2. Network overview — fully built this slice
            NetworkOverviewSection(),
            SizedBox(height: 12),

            // 3. People you may know — fully built (F-N3)
            SuggestionsSection(),
            SizedBox(height: 12),

            // 4. Popular on Skillora — follow suggestions (F-N4)
            FollowSuggestionsSection(),
          ],
        ),
      ),
    );
  }
}
