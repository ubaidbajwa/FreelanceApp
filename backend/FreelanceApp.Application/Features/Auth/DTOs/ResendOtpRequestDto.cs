using System.ComponentModel.DataAnnotations;

namespace FreelanceApp.Application.Features.Auth.DTOs;

public class ResendOtpRequestDto
{
    [Required(ErrorMessage = "Email is required")]
    [EmailAddress(ErrorMessage = "Invalid email format")]
    public string Email { get; set; } = string.Empty;
}