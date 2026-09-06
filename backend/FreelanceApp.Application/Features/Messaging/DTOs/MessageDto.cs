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

    // ===== Media fields (M-M4, additive, nullable) — set only for Type Image/Video =====
    // Body carries the caption (may be empty). MediaPublicId is deliberately NOT here — the public id
    // is a server-only deletion handle and must never leak to a client. Width/Height let the client
    // reserve layout space before the image loads so the message list doesn't jump. For a tombstone
    // (IsDeleted) MediaUrl and MediaThumbnailUrl are blanked in SQL, exactly like Body.
    public string? MediaUrl { get; set; }
    public string? MediaThumbnailUrl { get; set; }
    public int? MediaWidth { get; set; }
    public int? MediaHeight { get; set; }
    public int? MediaDurationMs { get; set; }
    public string? MediaMimeType { get; set; }

    // Document original filename (M-M8) — set only for Type File. The client shows this as the document's
    // label (contract_final_v3.pdf) and renders an icon from its extension. Already sanitised server-side.
    // Blanked (null) for a tombstone in SQL, like the URLs — a filename leaks meaning even when gone.
    public string? MediaFileName { get; set; }

    // Voice waveform (M-M6) — comma-separated amplitude samples (each 0–100, ≤64), computed by the
    // client. Null for image/video, for a voice note with no samples, and for a tombstone (blanked in
    // SQL like the URLs). The client renders a flat bar when null.
    public string? MediaWaveform { get; set; }

    // ===== Voice "played" receipts (M-M7, caller-relative) — meaningful only for Type Voice =====
    // Resolved by correlated EXISTS subqueries in ProjectMessage (index seeks on MessagePlays), not a
    // projected collection. Both are blanked (false) for a tombstone, like the media fields above.
    // playedByMe: the caller has played this voice note. playedByOther: the other participant has.
    public bool PlayedByMe { get; set; }
    public bool PlayedByOther { get; set; }
}
