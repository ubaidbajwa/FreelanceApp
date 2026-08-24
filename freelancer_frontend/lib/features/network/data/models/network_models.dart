// Backend Network DTOs ke Flutter twins — exact same fields.
// (FreelanceApp.Application/Features/Network/DTOs/ se mirror kiye gaye)

class NetworkOverview {
  final int connectionsCount;
  final int invitesSentCount;
  final int invitesReceivedCount;
  final int followingCount;
  final int followersCount;

  const NetworkOverview({
    required this.connectionsCount,
    required this.invitesSentCount,
    required this.invitesReceivedCount,
    required this.followingCount,
    required this.followersCount,
  });

  factory NetworkOverview.fromJson(Map<String, dynamic> json) => NetworkOverview(
        connectionsCount: json['connectionsCount'] as int? ?? 0,
        invitesSentCount: json['invitesSentCount'] as int? ?? 0,
        invitesReceivedCount: json['invitesReceivedCount'] as int? ?? 0,
        followingCount: json['followingCount'] as int? ?? 0,
        followersCount: json['followersCount'] as int? ?? 0,
      );
}

// GET /suggestions ka twin — scored suggestion card
class Suggestion {
  final String userId;
  final String fullName;
  final String? headline;
  final String? photoUrl;
  final int mutualConnectionsCount;
  final List<String> sharedSkills;
  final int score;

  const Suggestion({
    required this.userId,
    required this.fullName,
    this.headline,
    this.photoUrl,
    required this.mutualConnectionsCount,
    required this.sharedSkills,
    required this.score,
  });

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String? ?? '',
        headline: json['headline'] as String?,
        photoUrl: json['photoUrl'] as String?,
        mutualConnectionsCount: json['mutualConnectionsCount'] as int? ?? 0,
        sharedSkills: (json['sharedSkills'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        score: json['score'] as int? ?? 0,
      );
}

// GET /followers, /following ka twin
class FollowUser {
  final String userId;
  final String fullName;
  final String? headline;
  final String? photoUrl;
  final bool isFollowingBack;

  const FollowUser({
    required this.userId,
    required this.fullName,
    this.headline,
    this.photoUrl,
    required this.isFollowingBack,
  });

  factory FollowUser.fromJson(Map<String, dynamic> json) => FollowUser(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String? ?? '',
        headline: json['headline'] as String?,
        photoUrl: json['photoUrl'] as String?,
        isFollowingBack: json['isFollowingBack'] as bool? ?? false,
      );
}

// GET /follow-suggestions ka social proof preview user
class SocialProofUser {
  final String userId;
  final String fullName;
  final String? photoUrl;

  const SocialProofUser({
    required this.userId,
    required this.fullName,
    this.photoUrl,
  });

  factory SocialProofUser.fromJson(Map<String, dynamic> json) => SocialProofUser(
        userId: json['userId'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        photoUrl: json['photoUrl'] as String?,
      );
}

// GET /follow-suggestions ka twin — globally popular users scored for discovery
class FollowSuggestion {
  final String userId;
  final String fullName;
  final String? headline;
  final String? photoUrl;
  final int followersCount;
  final List<String> sharedSkills;
  final int score;
  // Backend caps at 3; never null — safe fallback to const [] for older builds
  final List<SocialProofUser> followedByPreview;

  const FollowSuggestion({
    required this.userId,
    required this.fullName,
    this.headline,
    this.photoUrl,
    required this.followersCount,
    required this.sharedSkills,
    required this.score,
    required this.followedByPreview,
  });

  factory FollowSuggestion.fromJson(Map<String, dynamic> json) => FollowSuggestion(
        userId: json['userId'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        headline: json['headline'] as String?,
        photoUrl: json['photoUrl'] as String?,
        followersCount: json['followersCount'] as int? ?? 0,
        sharedSkills: (json['sharedSkills'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        score: json['score'] as int? ?? 0,
        followedByPreview: (json['followedByPreview'] as List<dynamic>?)
                ?.map((e) => SocialProofUser.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

// GET /follow/{userId}/status ka twin
class FollowStatus {
  final bool isFollowing;
  final bool isFollowedBy;

  const FollowStatus({
    required this.isFollowing,
    required this.isFollowedBy,
  });

  factory FollowStatus.fromJson(Map<String, dynamic> json) => FollowStatus(
        isFollowing: json['isFollowing'] as bool? ?? false,
        isFollowedBy: json['isFollowedBy'] as bool? ?? false,
      );
}
