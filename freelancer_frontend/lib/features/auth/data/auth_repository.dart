import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import 'models/register_request.dart';
import 'models/auth_response.dart';
import 'models/login_request.dart';
import 'models/resend_otp_request.dart';
import 'models/verify_email_request.dart';
import 'models/forgot_password_request.dart';
import 'models/reset_password_request.dart';

class AuthRepository {
  final Dio _dio;
  AuthRepository(this._dio);

  // Register pe tokens NAHI milte — backend sirf { message } deta hai
  // (email verify flow: register → verify-email → login, tab jaake tokens)
  Future<String> register(RegisterRequest request) async {
    final response = await _dio.post(
      ApiConstants.register,
      data: request.toJson(), // Dart → JSON
    );
    return response.data['message']; // "Registration received..."
  }

  // Signup step 0 — email pehle se registered hai? true/false
  Future<bool> emailExists(String email) async {
    final response = await _dio.post(
      ApiConstants.checkEmail,
      data: {'email': email},
    );
    return response.data['exists'] == true;
  }

  // Verify email — success = 204, koi response body NAHI
  // isliye return type Future<void> (kuch parse nahi karna)
  Future<void> verifyEmail(VerifyEmailRequest request) async {
    await _dio.post(
      ApiConstants.verifyEmail,
      data: request.toJson(),
    );
  }

  // Resend OTP — success = 200, generic message (usay bhi ignore kar sakte ho)
  Future<void> resendOtp(ResendOtpRequest request) async {
    await _dio.post(
      ApiConstants.resendOtp,
      data: request.toJson(),
    );
  }

  // Forgot password — 200 + generic message (enumeration-safe, message ignore)
  Future<void> forgotPassword(ForgotPasswordRequest request) async {
    await _dio.post(
      ApiConstants.forgotPassword,
      data: request.toJson(),
    );
  }

  // Reset password — 200 + message, naya password set ho gaya
  Future<void> resetPassword(ResetPasswordRequest request) async {
    await _dio.post(
      ApiConstants.resetPassword,
      data: request.toJson(),
    );
  }

  // Login pe hi AuthResponse (tokens + user) milta hai
  Future<AuthResponse> login(LoginRequest request) async {
    final response = await _dio.post(
      ApiConstants.login,
      data: request.toJson(), // Dart → JSON
    );
    return AuthResponse.fromJson(response.data); // JSON → Dart
  }

  // Google Sign-In — Flutter se sirf idToken bhejte hain; backend usay verify
  // kar ke find-or-create karta hai aur wahi AuthResponse (tokens + user) deta
  // hai jo normal login deta — isliye success flow bilkul same reuse hota hai
  Future<AuthResponse> googleLogin(String idToken) async {
    final response = await _dio.post(
      ApiConstants.google,
      data: {'idToken': idToken},
    );
    return AuthResponse.fromJson(response.data);
  }
}

// Provider — dio inject ho raha hai (DI chain: dioProvider → authRepository)
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider));
});
