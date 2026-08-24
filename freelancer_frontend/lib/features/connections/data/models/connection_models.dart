// Backend Connections DTOs ke Flutter twins — exact same fields.
// (FreelanceApp.Application/Features/Connections/DTOs/ se mirror kiye gaye)

// ConnectionUserDto ka twin — doosray user ka card (lists + pending requests)
class ConnectionUser {
  final String userId;
  final String name;
  final String? headline;
  final String? profilePhotoUrl;

  const ConnectionUser({
    required this.userId,
    required this.name,
    this.headline,
    this.profilePhotoUrl,
  });

  factory ConnectionUser.fromJson(Map<String, dynamic> json) => ConnectionUser(
        userId: json['userId'] as String,
        name: json['name'] as String? ?? '',
        headline: json['headline'] as String?,
        profilePhotoUrl: json['profilePhotoUrl'] as String?,
      );
}

// Mutual connection preview — GET /requests/incoming ka additional field.
// Max 3 items; default empty so an older backend build does not crash the app.
class MutualPreview {
  final String userId;
  final String fullName;
  final String? photoUrl;

  const MutualPreview({
    required this.userId,
    required this.fullName,
    this.photoUrl,
  });

  factory MutualPreview.fromJson(Map<String, dynamic> json) => MutualPreview(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String? ?? '',
        photoUrl: json['photoUrl'] as String?,
      );
}

// PendingRequestDto ka twin — incoming/outgoing pending request
class PendingRequest {
  final String connectionId;
  final ConnectionUser user;
  final DateTime createdAt;
  // New fields present only on incoming items; default to 0/[] so outgoing
  // items and older backend builds parse safely.
  final int mutualConnectionsCount;
  final List<MutualPreview> mutualPreview;

  const PendingRequest({
    required this.connectionId,
    required this.user,
    required this.createdAt,
    this.mutualConnectionsCount = 0,
    this.mutualPreview = const [],
  });

  factory PendingRequest.fromJson(Map<String, dynamic> json) => PendingRequest(
        connectionId: json['connectionId'] as String,
        user: ConnectionUser.fromJson(json['user'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String),
        mutualConnectionsCount: json['mutualConnectionsCount'] as int? ?? 0,
        mutualPreview: (json['mutualPreview'] as List<dynamic>?)
                ?.map((e) => MutualPreview.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

// ConnectionRequestResponseDto ka twin — POST /requests ka jawab.
// Status INT aata hai (0=Pending, 1=Accepted, 2=Rejected) — backend mein
// JsonStringEnumConverter registered nahi (RegisterRequest wala hi pattern).
class ConnectionRequestResponse {
  final String id;
  final String requesterId;
  final String receiverId;
  final int status; // 0=Pending, 1=Accepted, 2=Rejected
  final DateTime createdAt;
  final DateTime? respondedAt;

  const ConnectionRequestResponse({
    required this.id,
    required this.requesterId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  factory ConnectionRequestResponse.fromJson(Map<String, dynamic> json) =>
      ConnectionRequestResponse(
        id: json['id'] as String,
        requesterId: json['requesterId'] as String,
        receiverId: json['receiverId'] as String,
        status: json['status'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        respondedAt: json['respondedAt'] == null
            ? null
            : DateTime.parse(json['respondedAt'] as String),
      );
}

// GET /status/{otherUserId} — dusre user ke sath rishta kya hai.
// Backend string bhejta hai: "None" | "PendingOutgoing" | "PendingIncoming" | "Connected"
enum ConnectionStatusWith {
  none,
  pendingOutgoing, // maine bheji hui request pending hai
  pendingIncoming, // usne mujhe bheji hui request pending hai
  connected;

  static ConnectionStatusWith fromApi(String value) => switch (value) {
        'PendingOutgoing' => ConnectionStatusWith.pendingOutgoing,
        'PendingIncoming' => ConnectionStatusWith.pendingIncoming,
        'Connected' => ConnectionStatusWith.connected,
        _ => ConnectionStatusWith.none,
      };
}
