import '../../../../core/constants/user_role.dart';

// Backend ke RegisterRequestDto ka Flutter twin — exact same fields
class RegisterRequest {
  final String email;
  final String password;
  final String fullName;
  final UserRole role; // type-safe enum — string typo ka koi chance nahi
  // reCAPTCHA v2 (checkbox) token — backend required (NotEmpty). Dev mein backend
  // Captcha:Enabled=false pe verify nahi karta, par token phir bhi bhejna hota hai.
  final String captchaToken;

  const RegisterRequest({
    required this.email,
    required this.password,
    required this.fullName,
    required this.role,
    required this.captchaToken,
  });

  // Dart object → JSON (request body banane ke liye)
  // Role INT jata hai (0=Freelancer, 1=Client) — backend mein
  // JsonStringEnumConverter registered nahi, is liye "Freelancer" string 400 degi
  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
    'fullName': fullName,
    'role': role.value,
    'captchaToken': captchaToken,
  };
}
