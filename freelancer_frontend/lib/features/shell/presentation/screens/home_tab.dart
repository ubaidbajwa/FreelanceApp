import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/profile_summary_notifier.dart';
import '../widgets/banner_carousel.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  // Session ke liye dismiss — app restart pe wapas aata hai (intentional)
  bool _bannerDismissed = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileSummaryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 88), // FAB ke liye space
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // Banner carousel — profile load hone ke baad dikhata hai
          if (!_bannerDismissed && !profile.loading)
            BannerCarousel(
              profile: profile,
              onDismiss: () => setState(() => _bannerDismissed = true),
            ),

          // Feed placeholder
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _navy.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 48,
                    color: _navy.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Your feed is coming soon',
                    style: TextStyle(
                      color: _navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Posts and updates from your network will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _navy.withValues(alpha: 0.5),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '// TODO: posts module',
                    style: TextStyle(
                      color: _gold.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
