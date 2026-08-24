import '../application/profile_summary_notifier.dart';

// Role-aware banner cards. Yahan sirf config hai — no widgets.
// Done check bhi yahan hota hai taake carousel widget generic rahe.

enum BannerCardId { completeProfile, addPhoto, getVerified, findPeople }

class BannerCard {
  final BannerCardId id;
  final String title;
  final String body;
  final String actionLabel;
  final String? route; // null = no-op (TODO: woh module abhi nahi bana)

  const BannerCard({
    required this.id,
    required this.title,
    required this.body,
    required this.actionLabel,
    this.route,
  });
}

List<BannerCard> cardsForRole(int role) =>
    role == 1 ? _clientCards : _freelancerCards;

// Done = filtered out from carousel (approach chosen: filter, not dim).
bool isCardDone(BannerCardId id, ProfileSummaryState p) => switch (id) {
      BannerCardId.completeProfile => p.completionPercent >= 80,
      BannerCardId.addPhoto =>
        p.photoUrl != null && p.photoUrl!.isNotEmpty,
      BannerCardId.getVerified => false, // TODO: KYC module
      BannerCardId.findPeople => false, // TODO: connections count
    };

const _freelancerCards = [
  BannerCard(
    id: BannerCardId.completeProfile,
    title: 'Complete your profile',
    body: 'Clients see your profile first — make it count',
    actionLabel: 'Complete profile',
    route: '/profile-step1',
  ),
  BannerCard(
    id: BannerCardId.addPhoto,
    title: 'Add a profile photo',
    body: 'Profiles with photos get 3× more client views',
    actionLabel: 'Add photo',
    route: '/profile-step1',
  ),
  BannerCard(
    id: BannerCardId.getVerified,
    title: 'Get verified (KYC)',
    body: 'Stand out with a verified badge',
    actionLabel: 'Start verification',
    route: null, // TODO: KYC module
  ),
  BannerCard(
    id: BannerCardId.findPeople,
    title: 'Find people you know',
    body: 'Grow your network to unlock more opportunities',
    actionLabel: 'Browse people',
    route: '/people',
  ),
];

const _clientCards = [
  BannerCard(
    id: BannerCardId.completeProfile,
    title: 'Complete your profile',
    body: "Let freelancers know who they're working with",
    actionLabel: 'Complete profile',
    route: '/profile-step1',
  ),
  BannerCard(
    id: BannerCardId.addPhoto,
    title: 'Add a profile photo',
    body: 'A photo builds trust with top talent',
    actionLabel: 'Add photo',
    route: '/profile-step1',
  ),
  BannerCard(
    id: BannerCardId.getVerified,
    title: 'Get verified',
    body: 'Verified clients receive faster responses',
    actionLabel: 'Start KYC',
    route: null, // TODO: KYC module
  ),
  BannerCard(
    id: BannerCardId.findPeople,
    title: 'Find freelancers',
    body: 'Discover top verified talent for your projects',
    actionLabel: 'Browse talent',
    route: '/people',
  ),
];
