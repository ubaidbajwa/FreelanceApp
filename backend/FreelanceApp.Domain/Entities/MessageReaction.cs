namespace FreelanceApp.Domain.Entities;

// One reaction per user per message — composite PK (MessageId, UserId). Reacting again
// REPLACES the previous emoji (update in place) rather than adding a second row; this matches
// WhatsApp and keeps the per-message aggregate cheap (bounded by participant count, not history).
public class MessageReaction
{
    public Guid MessageId { get; set; }   // composite PK part
    public Guid UserId { get; set; }      // composite PK part

    // Max 16 — enough for a multi-codepoint emoji with ZWJ sequences and skin-tone modifiers.
    // A single "emoji" is frequently several UTF-16 code units, so max 1/2 would truncate.
    public string Emoji { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; }

    // ===== Navigation Properties =====
    public Message? Message { get; set; }
}
