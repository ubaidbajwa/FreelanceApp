namespace FreelanceApp.Application.Features.Messaging.DTOs;

// The "other" participant in a 1:1 conversation — mirrors ConnectionUserDto's shape
// (public profile fields only, no email/secrets).
public class ConversationUserDto
{
    public Guid UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string? Headline { get; set; }
    public string? PhotoUrl { get; set; }
}
