using System.ComponentModel.DataAnnotations;

namespace FreelanceApp.Application.Features.Auth.DTOs;

public class ChangePasswordRequestDto
{
    [Required(ErrorMessage = "Current password is required")]
    public string CurrentPassword { get; set; } = string.Empty;

    // NewPassword ki validation ChangePasswordRequestValidator (FluentValidation)
    // mein hai — strong policy (upper/lower/digit/special) wahan apply hoti hai.
    public string NewPassword { get; set; } = string.Empty;
}
