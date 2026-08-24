namespace FreelanceApp.Application.Features.Messaging.DTOs;

// Body of PUT /api/conversations/{id}/messages/{messageId}/reaction — set (or replace) the
// caller's reaction on a message. Removing a reaction uses DELETE (no body).
public class ReactRequestDto
{
    public string Emoji { get; set; } = string.Empty;
}
