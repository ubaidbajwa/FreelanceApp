class ResendOtpRequest {
  final String email;

  const ResendOtpRequest({required this.email});

  Map<String, dynamic> toJson() => {
        'email': email,
      };
}
