using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Messaging.DTOs;

// A single message on the wire.
public class MessageDto
{
    public Guid Id { get; set; }
    public Guid ConversationId { get; set; }
    public Guid SenderId { get; set; }
    public string Body { get; set; } = string.Empty;
    public MessageType Type { get; set; }   // JSON mein int
    public DateTime CreatedAt { get; set; }

    // Tombstone flag for "delete for everyone". When true the Body is blanked server-side and the
    // client renders "This message was deleted". ("Delete for me" never reaches the wire — the row
    // is excluded from that user's page entirely.)
    public bool IsDeleted { get; set; }

    // ===== Message actions (M1.2, additive) =====

    // The quoted message, resolved in the SAME projection (correlated subquery — no N+1).
    // Null when this message is not a reply.
    public MessageReplyDto? ReplyTo { get; set; }

    // Aggregated reactions for this message (emoji, count, and whether the CALLER reacted with it).
    // NOT a raw per-row list. Attached from a single aggregate query keyed by the page's message ids.
    public List<MessageReactionSummaryDto> Reactions { get; set; } = [];

    // null = never edited.
    public DateTime? EditedAt { get; set; }

    // Pin state (conversation-scoped). PinnedByUserId and PinExpiresAt are null when not pinned.
    // IsPinned is false once PinExpiresAt passes (query-time filtering — no background sweeper).
    public bool IsPinned { get; set; }
    public Guid? PinnedByUserId { get; set; }
    public DateTime? PinExpiresAt { get; set; }

    // True when this message was created by a forward (ForwardedFromMessageId set) — drives the
    // "Forwarded" label. The source id itself is not leaked (it may live in a conversation the
    // caller can't see).
    public bool IsForwarded { get; set; }

    // System message fields — null for normal messages (Type != System).
    // Body is always empty; client renders the sentence from these two fields and SenderId.
    public SystemEventType? SystemEventType { get; set; }
    public Guid? SystemTargetMessageId { get; set; }
}
