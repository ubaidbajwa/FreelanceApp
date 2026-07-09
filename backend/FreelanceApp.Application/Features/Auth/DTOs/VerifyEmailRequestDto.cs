using System.ComponentModel.DataAnnotations;

namespace FreelanceApp.Application.Features.Auth.DTOs;

public class VerifyEmailRequestDto
{
    [Required(ErrorMessage = "Email is required")]
    [EmailAddress(ErrorMessage = "Invalid email format")]
    public string Email { get; set; } = string.Empty;

    [Required(ErrorMessage = "OTP is required")]
    [RegularExpression(@"^\d{6}$", ErrorMessage = "OTP must be exactly 6 digits")]
    public string Otp { get; set; } = string.Empty;
}