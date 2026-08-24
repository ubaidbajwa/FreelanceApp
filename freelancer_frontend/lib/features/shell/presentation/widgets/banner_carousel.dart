import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../application/profile_summary_notifier.dart';
import '../../config/banner_cards_config.dart';

// Saari 4 cards hamesha show hoti hain.
// Done cards completed state mein dikhti hain (dimmed + check icon).

class BannerCarousel extends StatefulWidget {
  final ProfileSummaryState profile;
  final VoidCallback onDismiss;

  const BannerCarousel({
    super.key,
    required this.profile,
    required this.onDismiss,
  });

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = cardsForRole(widget.profile.role);
    final doneCount =
        cards.where((c) => isCardDone(c.id, widget.profile)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GETTING STARTED',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$doneCount/${cards.length} complete',
                      style: TextStyle(
                        color: _navy.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close,
                    color: _navy.withValues(alpha: 0.45), size: 20),
                onPressed: widget.onDismiss,
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),

        // Card carousel — saari 4 cards
        SizedBox(
          height: 190,
          child: PageView.builder(
            controller: _pageController,
            itemCount: cards.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final card = cards[index];
              final done = isCardDone(card.id, widget.profile);
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: index == cards.length - 1 ? 16 : 8,
                ),
                child: _BannerCardWidget(card: card, done: done),
              );
            },
          ),
        ),

        // Dot indicator
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(cards.length, (i) {
              final active = i == _currentPage;
              final done = isCardDone(cards[i].id, widget.profile);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  // Done dot = gold, active = navy, rest = muted
                  color: active
                      ? _navy
                      : done
                          ? _gold.withValues(alpha: 0.6)
                          : _navy.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _BannerCardWidget extends StatelessWidget {
  final BannerCard card;
  final bool done;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  const _BannerCardWidget({required this.card, required this.done});

  IconData get _icon => switch (card.id) {
        BannerCardId.completeProfile => Icons.person_outline,
        BannerCardId.addPhoto => Icons.add_a_photo_outlined,
        BannerCardId.getVerified => Icons.verified_outlined,
        BannerCardId.findPeople => Icons.people_outline,
      };

  @override
  Widget build(BuildContext context) {
    final hasRoute = card.route != null;

    return Container(
      decoration: BoxDecoration(
        // Done card: slightly dimmed background
        color: done ? const Color(0xFFF4F4F2) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: done ? 0.03 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon circle — done pe gold ring + check overlay
          Stack(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: done ? _gold.withValues(alpha: 0.15) : _navy,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _icon,
                  color: done ? _gold : _gold,
                  size: 24,
                ),
              ),
              if (done)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: _gold,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // Text + button
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.title,
                  style: TextStyle(
                    color: done
                        ? _navy.withValues(alpha: 0.45)
                        : _navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  card.body,
                  style: TextStyle(
                    color: _navy.withValues(alpha: done ? 0.35 : 0.55),
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                // Done = "Completed" chip, pending = action button
                done
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _gold.withValues(alpha: 0.35), width: 1),
                        ),
                        child: Text(
                          'Completed',
                          style: TextStyle(
                            color: _gold.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                          side: BorderSide(
                            color: hasRoute
                                ? _navy
                                : _navy.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 9),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: hasRoute ? () => context.go(card.route!) : null,
                        child: Text(
                          card.actionLabel,
                          style: TextStyle(
                            color: hasRoute
                                ? _navy
                                : _navy.withValues(alpha: 0.35),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
