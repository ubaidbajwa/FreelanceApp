using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Domain.Entities;

public class Message
{
    public Guid Id { get; set; }
    public Guid ConversationId { get; set; }     // FK to Conversation
    public Guid SenderId { get; set; }           // FK to User

    public string Body { get; set; } = string.Empty;   // max 4000

    public MessageType Type { get; set; } = MessageType.Text;

    public DateTime CreatedAt { get; set; }

    // Soft delete for "delete for everyone" — null = live message. A non-null value is a shared
    // tombstone: BOTH participants see "This message was deleted". (Contrast: "delete for me" is a
    // per-user MessageDeletion row, never this column.)
    public DateTime? DeletedAt { get; set; }

    // ===== Message actions (M1.2, additive) =====

    // Reply: self-referencing FK to the quoted message. Restrict on delete (see MessageConfiguration)
    // — a reply must SURVIVE its quoted message being deleted and show a "message deleted" placeholder.
    public Guid? ReplyToMessageId { get; set; }

    // Edit: null = never edited. Set to UtcNow when the body is edited (within the edit window).
    public DateTime? EditedAt { get; set; }

    // Pin: null = not pinned. PinnedByUserId records who pinned it (pinning is conversation-scoped,
    // any participant may pin either party's message). Cleared together on unpin.
    public DateTime? PinnedAt { get; set; }
    public Guid? PinnedByUserId { get; set; }

    // Pin expiry: UTC instant after which the pin is treated as inactive by query-time filtering.
    // Null = never expires (legacy rows; pins created before duration was introduced).
    // Stored as an absolute timestamp — an absolute instant is unambiguous and doesn't silently
    // change meaning if the duration values are ever adjusted.
    public DateTime? PinExpiresAt { get; set; }

    // Forward: null = not forwarded. Points at the ORIGINAL message (often in another conversation)
    // purely to render a "Forwarded" label. Deliberately NOT a FK — the source lives elsewhere and
    // must be independently deletable; a Restrict FK would couple the two conversations' lifecycles.
    public Guid? ForwardedFromMessageId { get; set; }

    // System message fields — null for normal messages. Body stays empty for system messages.
    // SenderId is the actor, letting the client decide "You" vs. the sender's display name.
    public SystemEventType? SystemEventType { get; set; }
    public Guid? SystemTargetMessageId { get; set; }

    // ===== Navigation Properties =====
    public Conversation? Conversation { get; set; }
    public User? Sender { get; set; }

    // The quoted message (self-reference). Null when this message is not a reply.
    public Message? ReplyToMessage { get; set; }

    public ICollection<MessageReaction> Reactions { get; set; } = new List<MessageReaction>();
    public ICollection<MessageDeletion> Deletions { get; set; } = new List<MessageDeletion>();
}
