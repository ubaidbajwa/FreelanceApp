// Backend ke ResetPasswordRequestDto ka twin (Email, Otp, NewPassword)
// ConfirmPassword backend pe NAHI jata — wo sirf frontend UX check hai
class ResetPasswordRequest {
  final String email;
  final String otp;
  final String newPassword;

  const ResetPasswordRequest({
    required this.email,
    required this.otp,
    required this.newPassword,
  });

  Map<String, dynamic> toJson() => {
        'email': email,
        'otp': otp,
        'newPassword': newPassword, // camelCase — binding case-insensitive hai lekin convention yehi
      };
}
