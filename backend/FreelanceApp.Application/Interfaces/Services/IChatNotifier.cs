using FreelanceApp.Application.Features.Messaging.DTOs;

namespace FreelanceApp.Application.Interfaces.Services;

/// <summary>
/// Real-time push seam for the chat module. This is the Clean Architecture boundary:
/// ChatService depends on THIS interface, never on SignalR. The concrete implementation
/// (a SignalR hub adapter) lives in the Api project — so the Application project stays
/// free of Microsoft.AspNetCore.SignalR, ChatService stays unit-testable with a mock,
/// and swapping the transport later touches exactly one file.
/// </summary>
public interface IChatNotifier
{
    /// <summary>Push a newly-created message to every participant of its conversation.</summary>
    Task MessageReceivedAsync(IEnumerable<Guid> userIds, MessageDto message, CancellationToken ct = default);

    /// <summary>Notify a user that someone started a conversation request with them.</summary>
    Task ConversationRequestReceivedAsync(Guid userId, ConversationSummaryDto conversation, CancellationToken ct = default);

    /// <summary>Notify the initiator that their conversation request was accepted.</summary>
    Task ConversationAcceptedAsync(Guid userId, Guid conversationId, CancellationToken ct = default);

    // ===== Message actions (M1.2) — all persist-first, then notify all participants =====

    /// <summary>
    /// A message's reactions changed (added / replaced / removed). Payload is the aggregated
    /// buckets (emoji + count); ReactedByMe is not meaningful cross-user, so each client
    /// re-derives its own flag.
    /// </summary>
    Task ReactionChangedAsync(IEnumerable<Guid> userIds, Guid conversationId, Guid messageId,
        IReadOnlyList<MessageReactionSummaryDto> reactions, CancellationToken ct = default);

    /// <summary>A message was edited — carries the full updated MessageDto.</summary>
    Task MessageEditedAsync(IEnumerable<Guid> userIds, MessageDto message, CancellationToken ct = default);

    /// <summary>
    /// A message was deleted for EVERYONE (shared tombstone). Delete-for-me deliberately fires
    /// NO event — it is private to that user and firing it would leak their private deletion.
    /// </summary>
    Task MessageDeletedAsync(IEnumerable<Guid> userIds, Guid conversationId, Guid messageId, CancellationToken ct = default);

    /// <summary>
    /// A message was pinned or unpinned (conversation-scoped).
    /// pinExpiresAt is the UTC expiry when pinned (null when unpinned or never-expiring legacy pin).
    /// </summary>
    Task MessagePinChangedAsync(IEnumerable<Guid> userIds, Guid conversationId, Guid messageId,
        bool isPinned, DateTime? pinExpiresAt, CancellationToken ct = default);
}
