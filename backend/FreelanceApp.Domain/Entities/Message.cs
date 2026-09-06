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

    // ===== Media fields (M-M4, additive, ALL nullable) — populated only for Type Image/Video =====
    // Body doubles as the caption for media (required only for Text; empty string is valid for media).

    public string? MediaUrl { get; set; }            // Cloudinary secure URL of the full asset (max 500)
    public string? MediaThumbnailUrl { get; set; }   // Poster: image = resized variant, video = so_0 poster (max 500)
    public int? MediaWidth { get; set; }             // Intrinsic width  — client reserves layout space before load
    public int? MediaHeight { get; set; }            // Intrinsic height — without both, every incoming photo jumps the list
    public int? MediaDurationMs { get; set; }        // Video only (from Cloudinary's upload result)
    public long? MediaSizeBytes { get; set; }        // Asset size in bytes
    public string? MediaMimeType { get; set; }       // Validated declared content type (max 100)

    // Voice waveform (M-M6) — comma-separated amplitude samples (each 0–100, at most 64), computed by
    // the CLIENT while recording (no server-side audio decoding / ffmpeg). Null for image/video and for
    // a voice note whose client sent none — the client then falls back to a flat bar. Blanked in the
    // projection for a tombstone, exactly like the media URLs. Max 512 (64×3 digits + 63 commas ≤ 255).
    public string? MediaWaveform { get; set; }

    // Document original filename (M-M8) — max 255. Unlike a photo, a document's name IS content to the
    // user (contract_final_v3.pdf). SANITISED before it is stored (path components, null/control chars
    // and bidirectional-override characters stripped; extension forced to the validated type). Null for
    // non-document messages. Blanked in the projection for a tombstone, like the media URLs — a filename
    // (salary_negotiation_final.pdf) leaks meaning even when the file is gone.
    public string? MediaFileName { get; set; }       // max 255

    // Cloudinary public id — needed for later deletion. SERVER-ONLY: deliberately never on the wire
    // (not in MessageDto). A forward reuses this same id (a reference, not a copy), which is why
    // delete-for-everyone must NOT delete the Cloudinary asset — see docs/TODO.md.
    public string? MediaPublicId { get; set; }       // max 255

    // ===== Navigation Properties =====
    public Conversation? Conversation { get; set; }
    public User? Sender { get; set; }

    // The quoted message (self-reference). Null when this message is not a reply.
    public Message? ReplyToMessage { get; set; }

    public ICollection<MessageReaction> Reactions { get; set; } = new List<MessageReaction>();
    public ICollection<MessageDeletion> Deletions { get; set; } = new List<MessageDeletion>();

    // Per-user "played" records for a voice note (M-M7). Existence of a row = that user played it.
    public ICollection<MessagePlay> Plays { get; set; } = new List<MessagePlay>();
}
