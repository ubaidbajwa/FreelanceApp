import 'experience_model.dart';

// ConnectionInvitePolicy — backend int se match karta hai:
// 0=everyone (default), 1=mutualsOnly, 2=noOne
// Null backend response → everyone (safe default, most permissive)
enum ConnectionInvitePolicy { everyone, mutualsOnly, noOne }

// Profile ka data model — backend se jo JSON aata hai usko
// Dart object mein badalta hai (UserModel jaisa hi kaam)
class ProfileModel {
  final String? displayName;
  final String? headline;
  final String? bio;
  final String? profilePhotoUrl;   // photo ka URL (Cloudinary se)
  final List<String> skills;       // skills ki list
  final List<ExperienceModel> experiences;
  final double? hourlyRate;
  final int? availability;         // 0=FullTime 1=PartTime 2=Custom
  final int? workPreference;       // 0=Remote 1=OnSite 2=Hybrid
  final int? availabilityStatus;   // 0=ActivelyLooking 1=OpenToOffers 2=NotLooking
  final List<String> desiredJobTitles;
  final List<String> desiredJobLocations;
  final String? country;
  final String? city;
  final int profileCompletionPercent;
  final ConnectionInvitePolicy invitePolicy; // defaults everyone when null

  ProfileModel({
    this.displayName,
    this.headline,
    this.bio,
    this.profilePhotoUrl,
    required this.skills,
    required this.experiences,
    this.hourlyRate,
    this.availability,
    this.workPreference,
    this.availabilityStatus,
    required this.desiredJobTitles,
    required this.desiredJobLocations,
    this.country,
    this.city,
    required this.profileCompletionPercent,
    this.invitePolicy = ConnectionInvitePolicy.everyone,
  });

  // JSON → Dart object (backend ka response parse karna)
  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      displayName: json['displayName'],
      headline: json['headline'],
      bio: json['bio'],
      profilePhotoUrl: json['profilePhotoUrl'],
      // skills null bhi ho sakti hain backend se — isliye ?? [] (khali list fallback)
      skills: List<String>.from(json['skills'] ?? []),
      experiences: (json['experiences'] as List? ?? [])
          .map((e) => ExperienceModel.fromJson(e))
          .toList(),
      // JSON number int ya double dono aa sakta hai — num dono handle karta hai
      hourlyRate: (json['hourlyRate'] as num?)?.toDouble(),
      availability: json['availability'],
      workPreference: json['workPreference'],
      availabilityStatus: json['availabilityStatus'],
      desiredJobTitles: List<String>.from(json['desiredJobTitles'] ?? []),
      desiredJobLocations: List<String>.from(json['desiredJobLocations'] ?? []),
      country: json['country'],
      city: json['city'],
      profileCompletionPercent: json['profileCompletionPercent'] ?? 0,
      invitePolicy: ConnectionInvitePolicy.values[json['invitePolicy'] as int? ?? 0],
    );
  }
}

// Update request — jo fields user ne bhari HAIN sirf wohi bhejo
// (partial update — yaad hai backend sirf non-null update karta hai?)
class UpdateProfileRequest {
  final String? displayName;
  final String? headline;
  final String? bio;
  final List<String>? skills;
  final double? hourlyRate;
  final int? availability;         // 0=FullTime 1=PartTime 2=Custom
  final int? workPreference;       // 0=Remote 1=OnSite 2=Hybrid
  final int? availabilityStatus;   // 0=ActivelyLooking 1=OpenToOffers 2=NotLooking
  final List<String>? desiredJobTitles;
  final List<String>? desiredJobLocations;
  final String? country;
  final String? city;
  final int? clientType;    // 0=Individual 1=Business (client "About you" step)
  final String? businessName;
  final List<String>? hiringInterests;  // client step: max 5 categories
  final int? hiringType;                // 0=OneTimeProject 1=OngoingWork
  final int? invitePolicy;             // ConnectionInvitePolicy.index (0/1/2)

  UpdateProfileRequest({
    this.displayName,
    this.headline,
    this.bio,
    this.skills,
    this.hourlyRate,
    this.availability,
    this.workPreference,
    this.availabilityStatus,
    this.desiredJobTitles,
    this.desiredJobLocations,
    this.country,
    this.city,
    this.clientType,
    this.businessName,
    this.hiringInterests,
    this.hiringType,
    this.invitePolicy,
  });

  Map<String, dynamic> toJson() {
    return {
      // "if (x != null)" ka matlab: null hai to JSON mein daalo hi mat
      if (displayName != null) 'displayName': displayName,
      if (headline != null) 'headline': headline,
      if (bio != null) 'bio': bio,
      if (skills != null) 'skills': skills,
      if (hourlyRate != null) 'hourlyRate': hourlyRate,
      if (availability != null) 'availability': availability,
      if (workPreference != null) 'workPreference': workPreference,
      if (availabilityStatus != null) 'availabilityStatus': availabilityStatus,
      if (desiredJobTitles != null) 'desiredJobTitles': desiredJobTitles,
      if (desiredJobLocations != null) 'desiredJobLocations': desiredJobLocations,
      if (country != null) 'country': country,
      if (city != null) 'city': city,
      if (clientType != null) 'clientType': clientType,
      if (businessName != null) 'businessName': businessName,
      if (hiringInterests != null) 'hiringInterests': hiringInterests,
      if (hiringType != null) 'hiringType': hiringType,
      if (invitePolicy != null) 'invitePolicy': invitePolicy,
    };
  }
}