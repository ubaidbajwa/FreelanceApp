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
    // For an uncaptioned photo/video this is empty, so the client renders a localised "Photo"/"Video"
    // label from LastMessageType instead — the label is NEVER stored server-side (it can't be
    // translated, and Skillora targets users in every country), exactly as system messages avoided.
    public string? LastMessagePreview { get; set; }

    // Type of the same last content message the preview came from (null if no messages). Lets the
    // client localise the preview for media with no caption. Resolved by one more correlated subquery
    // in the SAME list statement — no extra round-trip.
    public MessageType? LastMessageType { get; set; }

    public DateTime? LastMessageAt { get; set; }

    // Caller's unread count via the LastReadAt watermark (CreatedAt > LastReadAt AND SenderId != me).
    public int UnreadCount { get; set; }

    // The OTHER participant's read watermark, from the caller's perspective (null if they've never
    // read). Lets the sender render read ticks: a message is "read" when CreatedAt <= OtherLastReadAt.
    // One timestamp per conversation updates every bubble at once — no per-message flag needed.
    public DateTime? OtherLastReadAt { get; set; }
}
