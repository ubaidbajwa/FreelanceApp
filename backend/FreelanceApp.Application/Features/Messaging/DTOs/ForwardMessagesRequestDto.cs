namespace FreelanceApp.Application.Features.Messaging.DTOs;

// Body of POST /api/conversations/{id}/messages/forward — {id} is the SOURCE conversation.
// Forwards one or more of its messages into TargetConversationId, preserving order. The caller
// must be a participant in BOTH conversations, and rule (c) still applies to the target.
public class ForwardMessagesRequestDto
{
    public Guid TargetConversationId { get; set; }

    // Source message ids to forward, in the order the UI multi-selected them. Order is preserved.
    public List<Guid> MessageIds { get; set; } = [];
}
