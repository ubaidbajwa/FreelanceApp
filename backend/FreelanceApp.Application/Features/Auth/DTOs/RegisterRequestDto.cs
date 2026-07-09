using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Auth.DTOs;

public class RegisterRequestDto
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public UserRole Role { get; set; } = UserRole.Freelancer;
}