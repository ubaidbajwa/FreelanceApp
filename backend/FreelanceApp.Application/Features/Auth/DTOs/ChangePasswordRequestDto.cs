using System.ComponentModel.DataAnnotations;

namespace FreelanceApp.Application.Features.Auth.DTOs;

public class ChangePasswordRequestDto
{
    [Required(ErrorMessage = "Current password is required")]
    public string CurrentPassword { get; set; } = string.Empty;

    [Required(ErrorMessage = "New password is required")]
    [MinLength(8, ErrorMessage = "Password must be at least 8 characters")]
    [MaxLength(100, ErrorMessage = "Password too long")]
    public string NewPassword { get; set; } = string.Empty;
}
