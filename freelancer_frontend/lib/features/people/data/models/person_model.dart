// Backend People DTOs ke Flutter twins.
// connectionStatus vocabulary connections slice jaisa hi hai — isi liye
// wahan wala ConnectionStatusWith enum REUSE kar rahe hain (naya nahi banaya).
// PagedResult<T> ab core/models/paged_result.dart mein hai (shared across features).
import '../../../connections/data/models/connection_models.dart';

// PersonDto ka twin — directory row (email/secrets nahi, sirf public fields)
class PersonModel {
  final String userId;
  final String fullName;
  final String? headline;
  final String? photoUrl;
  final ConnectionStatusWith connectionStatus;

  const PersonModel({
    required this.userId,
    required this.fullName,
    this.headline,
    this.photoUrl,
    required this.connectionStatus,
  });

  factory PersonModel.fromJson(Map<String, dynamic> json) => PersonModel(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String? ?? '',
        headline: json['headline'] as String?,
        photoUrl: json['photoUrl'] as String?,
        connectionStatus:
            ConnectionStatusWith.fromApi(json['connectionStatus'] as String),
      );

  // Pessimistic sendConnect ke baad sirf isi row ka status badalna hota hai
  PersonModel copyWith({ConnectionStatusWith? connectionStatus}) => PersonModel(
        userId: userId,
        fullName: fullName,
        headline: headline,
        photoUrl: photoUrl,
        connectionStatus: connectionStatus ?? this.connectionStatus,
      );
}

