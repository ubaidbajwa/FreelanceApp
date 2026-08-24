using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Auth.DTOs;

public class RegisterRequestDto
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public UserRole Role { get; set; } = UserRole.Freelancer;

    // Client-supplied captcha token (e.g. reCAPTCHA). Verified server-side
    // before any account is created. Requiredness enforced by the validator
    // so a missing token flows through the RFC 7807 validation path.
    public string CaptchaToken { get; set; } = string.Empty;
}