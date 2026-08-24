using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Messaging.DTOs;

// One row in the conversation list (accepted) or requests list (pending).
// Everything here is produced by a single projected query — see ConversationRepository.
public class ConversationSummaryDto
{
    public Guid Id { get; set; }
    public ConversationStatus Status { get; set; }   // JSON mein int

    // True when this is an incoming request: Pending AND someone else started it.
    // Lets the frontend render the request/accept UI without re-deriving from Status + initiator.
    public bool IsRequest { get; set; }

    public ConversationUserDto OtherUser { get; set; } = new();

    // Last message body truncated to 120 chars for the list preview; null if no messages.
    public string? LastMessagePreview { get; set; }

    public DateTime? LastMessageAt { get; set; }

    // Caller's unread count via the LastReadAt watermark (CreatedAt > LastReadAt AND SenderId != me).
    public int UnreadCount { get; set; }
}
