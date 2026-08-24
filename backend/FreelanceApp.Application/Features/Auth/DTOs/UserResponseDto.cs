using FreelanceApp.Application.Common.Capabilities;

namespace FreelanceApp.Application.Features.Auth.DTOs;

public class UserResponseDto
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;

    // "Role" (name kept for API compatibility) is the user's PRIMARY role — the default
    // experience only. Actual permissions live in Capabilities below.
    public string Role { get; set; } = string.Empty;
    public bool IsIdentityVerified { get; set; }
    public DateTime CreatedAt { get; set; }

    // Additive — computed capabilities (what the user can actually do).
    public UserCapabilitiesDto Capabilities { get; set; } = new();
}