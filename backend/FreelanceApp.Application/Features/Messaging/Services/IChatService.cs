using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Messaging.DTOs;

namespace FreelanceApp.Application.Features.Messaging.Services;

public interface IChatService
{
    /// <summary>Get-or-create the 1:1 conversation with a recipient; returns the caller's summary view.</summary>
    Task<ConversationSummaryDto> StartOrGetConversationAsync(Guid recipientId, CancellationToken ct = default);

    /// <summary>
    /// Fetch a single conversation as the caller's summary view (correct isRequest/unreadCount for them).
    /// Caller must be a participant (else 403); unknown id is 404. Unlike the list queries this does NOT
    /// exclude message-less threads — the get-or-create / cold-deep-link / push-tap path must resolve a
    /// freshly created conversation before any message exists.
    /// </summary>
    Task<ConversationSummaryDto> GetConversationAsync(Guid conversationId, CancellationToken ct = default);

    /// <summary>Send a message (enforces the pending-request 1-message rule and implicit accept-on-reply).</summary>
    Task<MessageDto> SendMessageAsync(Guid conversationId, SendMessageRequestDto dto, CancellationToken ct = default);

    Task AcceptAsync(Guid conversationId, CancellationToken ct = default);
    Task DeclineAsync(Guid conversationId, CancellationToken ct = default);

    Task<PagedResult<ConversationSummaryDto>> GetConversationsAsync(int page, int pageSize, CancellationToken ct = default);
    Task<PagedResult<ConversationSummaryDto>> GetRequestsAsync(int page, int pageSize, CancellationToken ct = default);

    Task<MessagePageDto> GetMessagesAsync(Guid conversationId, DateTime? before, int limit, CancellationToken ct = default);

    Task MarkReadAsync(Guid conversationId, CancellationToken ct = default);

    // ===== Message actions (M1.2) =====

    /// <summary>Set (or replace) the caller's reaction on a message. Returns the caller-relative aggregate.</summary>
    Task<IReadOnlyList<MessageReactionSummaryDto>> ReactAsync(Guid conversationId, Guid messageId, string emoji, CancellationToken ct = default);

    /// <summary>Remove the caller's reaction (idempotent).</summary>
    Task RemoveReactionAsync(Guid conversationId, Guid messageId, CancellationToken ct = default);

    /// <summary>Edit an own message within the edit window; returns the updated message.</summary>
    Task<MessageDto> EditMessageAsync(Guid conversationId, Guid messageId, string body, CancellationToken ct = default);

    /// <summary>
    /// Pin a message with a chosen duration. Re-pinning an already-active pin changes the duration without
    /// consuming cap. At the cap: 409 when ReplaceOldest=false; atomically replaces the oldest active pin
    /// when ReplaceOldest=true.
    /// </summary>
    Task PinAsync(Guid conversationId, Guid messageId, PinMessageRequestDto dto, CancellationToken ct = default);

    /// <summary>Unpin a message. Idempotent if not pinned.</summary>
    Task UnpinAsync(Guid conversationId, Guid messageId, CancellationToken ct = default);

    /// <summary>The conversation's pinned messages (bounded).</summary>
    Task<IReadOnlyList<MessageDto>> GetPinnedAsync(Guid conversationId, CancellationToken ct = default);

    /// <summary>Delete for everyone: own message, within window, idempotent — sets a shared tombstone.</summary>
    Task DeleteForEveryoneAsync(Guid conversationId, Guid messageId, CancellationToken ct = default);

    /// <summary>Delete for me: any visible message, no window, idempotent, invisible to the other party.</summary>
    Task DeleteForMeAsync(Guid conversationId, Guid messageId, CancellationToken ct = default);

    /// <summary>Forward one or more source-conversation messages into a target conversation (reuses the send path).</summary>
    Task<IReadOnlyList<MessageDto>> ForwardAsync(Guid sourceConversationId, ForwardMessagesRequestDto dto, CancellationToken ct = default);
}
