namespace FreelanceApp.Domain.Entities;

// A voice note was played by a user. Composite PK (MessageId, UserId) — one record per user per
// message, so marking a note played twice is naturally idempotent (the row already exists) rather
// than needing a guard. Mirrors MessageDeletion / MessageReaction: FK to Message → Cascade, FK to
// User → Restrict, index on MessageId for the played-flag projection. Only ever written for a
// MessageType.Voice message the user did NOT send (enforced in ChatService).
public class MessagePlay
{
    public Guid MessageId { get; set; }   // composite PK part
    public Guid UserId { get; set; }      // composite PK part

    public DateTime PlayedAt { get; set; }

    // ===== Navigation Properties =====
    public Message? Message { get; set; }
}
