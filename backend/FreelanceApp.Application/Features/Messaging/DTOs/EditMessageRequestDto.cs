namespace FreelanceApp.Application.Features.Messaging.DTOs;

// Body of PUT /api/conversations/{id}/messages/{messageId} — edit an own message within the edit window.
public class EditMessageRequestDto
{
    public string Body { get; set; } = string.Empty;
}
