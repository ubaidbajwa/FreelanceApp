// Saari API ki fixed values ek jagah — URL badla to sirf yahan change
class ApiConstants {
  ApiConstants._(); // private constructor — koi object na bana sake (static-only class)

  // adb reverse ki wajah se phone pe bhi localhost chalega
  static const String baseUrl = 'http://localhost:5186'; // 5104 → 5186

  // Endpoints — backend ke AuthController se exact match
  static const String register = '/api/auth/register';
  static const String checkEmail = '/api/auth/check-email';
  static const String login = '/api/auth/login';
  static const String verifyEmail = '/api/auth/verify-email';
  static const String resendOtp = '/api/auth/resend-otp';
  static const String forgotPassword = '/api/auth/forgot-password';
  static const String resetPassword = '/api/auth/reset-password';
  static const String google = '/api/auth/google';
  static const String refresh = '/api/auth/refresh';
  static const String logout = '/api/auth/logout';
  static const String me = '/api/users/me';
}
