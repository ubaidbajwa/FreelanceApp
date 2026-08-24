import 'user_model.dart';

// Backend ke AuthResponseDto ka twin (OAuth 2.0 format — aapka apna design!)
class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final DateTime expiresAt;
  final UserModel user;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresAt,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        accessToken: json['accessToken'],
        refreshToken: json['refreshToken'],
        tokenType: json['tokenType'],
        expiresAt: DateTime.parse(json['expiresAt']), // string → DateTime
        user: UserModel.fromJson(json['user']), // nested object — model ke andar model
      );
}