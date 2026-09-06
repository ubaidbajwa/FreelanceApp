using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Messaging.DTOs;
using FreelanceApp.Domain.Entities;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface IConversationRepository
{
    /// <summary>Loads a conversation with its Participants (tracked — for accept/decline writes).</summary>
    Task<Conversation?> GetByIdAsync(Guid id);

    /// <summary>
    /// Finds the existing 1:1 conversation between two users regardless of who initiated,
    /// or null. Includes Participants. Used to prevent duplicate threads.
    /// </summary>
    Task<Conversation?> FindBetweenAsync(Guid userA, Guid userB);

    /// <summary>
    /// One page of the caller's own conversations, newest-activity first: every accepted thread
    /// plus any still-pending thread the caller themselves initiated (their own outgoing request
    /// is simply their conversation — see IsRequest, which stays false for these). Declined threads
    /// are excluded. Each row is projected in a single query: other participant (id/name/photo/
    /// headline), last-message preview, and the caller's unread count. No per-row round-trips.
    /// </summary>
    Task<PagedResult<ConversationSummaryDto>> GetAcceptedPageAsync(
        Guid userId, int page, int pageSize, CancellationToken ct = default);

    /// <summary>
    /// One page of incoming message REQUESTS: Status = Pending AND InitiatorId != caller.
    /// Same single-query projection as the accepted list.
    /// </summary>
    Task<PagedResult<ConversationSummaryDto>> GetPendingRequestsPageAsync(
        Guid userId, int page, int pageSize, CancellationToken ct = default);

    /// <summary>
    /// Projects a SINGLE conversation to a summary from <paramref name="userId"/>'s perspective
    /// (same projection as the list pages). null if the user is not a participant. Used to return
    /// a summary after get-or-create and to build the request-received notification payload.
    /// </summary>
    Task<ConversationSummaryDto?> GetSummaryByIdAsync(
        Guid conversationId, Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Keyset page of a conversation's messages, newest-first, from <paramref name="userId"/>'s
    /// perspective. <paramref name="before"/> is an exclusive CreatedAt cursor (null = latest page).
    /// Excludes rows the caller "deleted for me"; includes "delete for everyone" rows as tombstones
    /// (body blanked, IsDeleted true). Resolves replyTo in-projection and attaches aggregated
    /// reactions in a single extra query — query count is independent of page size.
    /// </summary>
    Task<IReadOnlyList<MessageDto>> GetMessagesAsync(
        Guid conversationId, Guid userId, DateTime? before, int limit, CancellationToken ct = default);

    /// <summary>Count of messages a given user has sent in a conversation (drives the 1-message request rule).</summary>
    Task<int> CountMessagesBySenderAsync(Guid conversationId, Guid senderId, CancellationToken ct = default);

    /// <summary>True if the two users have an Accepted connection in either direction.</summary>
    Task<bool> AreConnectedAsync(Guid userA, Guid userB, CancellationToken ct = default);

    // ===== Message actions (M1.2) =====

    /// <summary>Single message, tracked (so edit/delete/pin mutations persist on SaveChanges). null if unknown.</summary>
    Task<Message?> GetMessageByIdAsync(Guid messageId);

    /// <summary>Projects a single message to a DTO from the caller's perspective (replyTo + reactions). null if unknown.</summary>
    Task<MessageDto?> GetMessageDtoAsync(Guid messageId, Guid userId, CancellationToken ct = default);

    /// <summary>Source messages (no tracking) belonging to <paramref name="conversationId"/> whose ids are in the set — for forward.</summary>
    Task<IReadOnlyList<Message>> GetMessagesByIdsAsync(Guid conversationId, IReadOnlyCollection<Guid> ids, CancellationToken ct = default);

    /// <summary>
    /// The conversation's ACTIVE pinned messages (bounded, ≤ cap), newest-pinned first, caller's perspective.
    /// Excludes expired pins (PinExpiresAt != null AND PinExpiresAt &lt;= UtcNow).
    /// </summary>
    Task<IReadOnlyList<MessageDto>> GetPinnedAsync(Guid conversationId, Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Count of ACTIVE pinned messages in a conversation (drives the pin cap).
    /// Expired pins are excluded — a pin counts as active only when PinnedAt IS NOT NULL
    /// AND (PinExpiresAt IS NULL OR PinExpiresAt &gt; UtcNow).
    /// </summary>
    Task<int> CountPinnedAsync(Guid conversationId, CancellationToken ct = default);

    /// <summary>
    /// The oldest ACTIVE pin in the conversation (lowest PinnedAt, not expired), tracked for replace-oldest.
    /// Returns null when no active pin exists.
    /// </summary>
    Task<Message?> GetOldestActivePinAsync(Guid conversationId, CancellationToken ct = default);

    // Reactions
    Task<MessageReaction?> GetReactionAsync(Guid messageId, Guid userId);
    Task AddReactionAsync(MessageReaction reaction);
    Task RemoveReactionAsync(MessageReaction reaction);

    /// <summary>Aggregated reaction buckets for one message. <paramref name="me"/> null ⇒ ReactedByMe false (used for fan-out payloads).</summary>
    Task<IReadOnlyList<MessageReactionSummaryDto>> GetReactionSummaryAsync(Guid messageId, Guid? me, CancellationToken ct = default);

    // Delete for me
    Task AddMessageDeletionAsync(MessageDeletion deletion);
    Task<bool> HasMessageDeletionAsync(Guid messageId, Guid userId, CancellationToken ct = default);

    // Voice "played" receipts (M-M7)
    Task AddMessagePlayAsync(MessagePlay play);

    /// <summary>True if a play record already exists for (message, user) — drives idempotency and the "no duplicate event" branch.</summary>
    Task<bool> HasMessagePlayAsync(Guid messageId, Guid userId, CancellationToken ct = default);

    // Unit-of-work style — Add* stage the entity; SaveChangesAsync commits (matches existing repos).
    Task AddAsync(Conversation conversation);
    Task AddMessageAsync(Message message);
    Task SaveChangesAsync();
}
