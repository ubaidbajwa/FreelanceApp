namespace FreelanceApp.Application.Features.Messaging.DTOs;

public class SendMessageRequestDto
{
    public string Body { get; set; } = string.Empty;

    // Optional: reply to an existing message in the SAME conversation. Reply needs no new endpoint.
    // A cross-conversation reply target is rejected (400) in ChatService.
    public Guid? ReplyToMessageId { get; set; }
}
