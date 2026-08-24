using FreelanceApp.Api.Hubs;
using FreelanceApp.Application.Features.Messaging.DTOs;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.SignalR;

namespace FreelanceApp.Api.Services;

/// <summary>
/// SignalR implementation of the IChatNotifier seam (Application never sees SignalR).
///
/// Lives in Api — not Infrastructure — because it depends on the ChatHub, an HTTP/transport
/// concern owned by the Api layer, exactly like CurrentUserService depends on HttpContext.
/// Infrastructure is reserved for external systems (DB, Redis, Cloudinary, email).
///
/// Targets users by id (Clients.User/Users), so every device a user is signed in on receives
/// the event. Event names are the exact strings the Flutter client binds to.
/// </summary>
public class SignalRChatNotifier(IHubContext<ChatHub> hub) : IChatNotifier
{
    public Task MessageReceivedAsync(IEnumerable<Guid> userIds, MessageDto message, CancellationToken ct = default)
    {
        var ids = userIds.Select(id => id.ToString()).ToList();
        return hub.Clients.Users(ids).SendAsync("MessageReceived", message, ct);
    }

    public Task ConversationRequestReceivedAsync(Guid userId, ConversationSummaryDto conversation, CancellationToken ct = default)
        => hub.Clients.User(userId.ToString()).SendAsync("ConversationRequestReceived", conversation, ct);

    public Task ConversationAcceptedAsync(Guid userId, Guid conversationId, CancellationToken ct = default)
        => hub.Clients.User(userId.ToString()).SendAsync("ConversationAccepted", conversationId, ct);

    // ===== Message actions (M1.2) =====

    public Task ReactionChangedAsync(IEnumerable<Guid> userIds, Guid conversationId, Guid messageId,
        IReadOnlyList<MessageReactionSummaryDto> reactions, CancellationToken ct = default)
    {
        var ids = userIds.Select(id => id.ToString()).ToList();
        return hub.Clients.Users(ids).SendAsync("ReactionChanged",
            new { conversationId, messageId, reactions }, ct);
    }

    public Task MessageEditedAsync(IEnumerable<Guid> userIds, MessageDto message, CancellationToken ct = default)
    {
        var ids = userIds.Select(id => id.ToString()).ToList();
        return hub.Clients.Users(ids).SendAsync("MessageEdited", message, ct);
    }

    public Task MessageDeletedAsync(IEnumerable<Guid> userIds, Guid conversationId, Guid messageId, CancellationToken ct = default)
    {
        var ids = userIds.Select(id => id.ToString()).ToList();
        return hub.Clients.Users(ids).SendAsync("MessageDeleted",
            new { conversationId, messageId }, ct);
    }

    public Task MessagePinChangedAsync(IEnumerable<Guid> userIds, Guid conversationId, Guid messageId,
        bool isPinned, DateTime? pinExpiresAt, CancellationToken ct = default)
    {
        var ids = userIds.Select(id => id.ToString()).ToList();
        return hub.Clients.Users(ids).SendAsync("MessagePinChanged",
            new { conversationId, messageId, isPinned, pinExpiresAt }, ct);
    }
}
