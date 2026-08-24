// Backend ke ForgotPasswordRequestDto ka twin — sirf email
class ForgotPasswordRequest {
  final String email;

  const ForgotPasswordRequest({required this.email});

  Map<String, dynamic> toJson() => {
        'email': email,
      };
}
