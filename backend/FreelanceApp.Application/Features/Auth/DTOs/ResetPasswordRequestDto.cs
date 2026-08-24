namespace FreelanceApp.Application.Features.Auth.DTOs;

// Validation ResetPasswordRequestValidator (FluentValidation) mein hai —
// DataAnnotations isi liye hataye taake duplicate error messages na aayen.
public class ResetPasswordRequestDto
{
    public string Email { get; set; } = string.Empty;

    public string Otp { get; set; } = string.Empty;

    public string NewPassword { get; set; } = string.Empty;
}