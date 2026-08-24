// Backend ke UserResponseDto ka twin
class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final bool isIdentityVerified; // backend: UserResponseDto.IsIdentityVerified
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isIdentityVerified,
    required this.createdAt,
  });

  // JSON → Dart object (response parhne ke liye)
  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        email: json['email'],
        fullName: json['fullName'],
        role: json['role'],
        isIdentityVerified: json['isIdentityVerified'] ?? false, // null aaye to false
        createdAt: DateTime.parse(json['createdAt']),
      );
}