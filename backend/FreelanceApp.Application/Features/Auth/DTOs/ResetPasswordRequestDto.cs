using System.ComponentModel.DataAnnotations;

namespace FreelanceApp.Application.Features.Auth.DTOs;

public class ResetPasswordRequestDto
{
    [Required(ErrorMessage = "Email is required")]
    [EmailAddress(ErrorMessage = "Invalid email format")]
    public string Email { get; set; } = string.Empty;

    [Required(ErrorMessage = "OTP is required")]
    [RegularExpression(@"^\d{6}$", ErrorMessage = "OTP must be exactly 6 digits")]
    public string Otp { get; set; } = string.Empty;

    [Required(ErrorMessage = "New password is required")]
    [MinLength(8, ErrorMessage = "Password must be at least 8 characters")]
    [MaxLength(100, ErrorMessage = "Password too long")]
    public string NewPassword { get; set; } = string.Empty;
}