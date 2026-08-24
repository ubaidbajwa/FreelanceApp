using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Messaging.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging;

namespace FreelanceApp.Application.Features.Messaging.Services;

public class ChatService(
    IConversationRepository conversations,
    IUserRepository userRepository,
    IChatNotifier chatNotifier,
    ICurrentUserService currentUser,
    ILogger<ChatService> logger) : IChatService
{
    // Paging clamp — same behavior as PeopleService (page >= 1, pageSize 1..50).
    public const int DefaultPageSize = 20;
    public const int MaxPageSize = 50;

    // Message page limit — cursor pages default to 30, clamped 1..50.
    public const int DefaultMessageLimit = 30;
    public const int MaxMessageLimit = 50;

    // ===== Message-action windows / caps (server-enforced — a client clock can't be trusted) =====

    // Edit window — WhatsApp's ~15 minutes. Beyond this an own message can no longer be edited.
    public static readonly TimeSpan EditWindow = TimeSpan.FromMinutes(15);

    // Delete-for-everyone window — WhatsApp's approximate 48 hours from send.
    public static readonly TimeSpan DeleteForEveryoneWindow = TimeSpan.FromHours(48);

    // Pin duration windows — stored as computed absolute UTC timestamps, not as a duration enum.
    public static readonly TimeSpan PinWindow24Hours = TimeSpan.FromHours(24);
    public static readonly TimeSpan PinWindow7Days   = TimeSpan.FromDays(7);
    public static readonly TimeSpan PinWindow30Days  = TimeSpan.FromDays(30);

    // Active pin cap (raised from 3 to 4). Expired pins are excluded from the count.
    // Beyond this, pin returns 409 (ReplaceOldest=false) or atomically replaces the oldest
    // active pin (ReplaceOldest=true).
    public const int MaxPinnedPerConversation = 4;

    // ===== START / GET =====

    public async Task<ConversationSummaryDto> StartOrGetConversationAsync(Guid recipientId, CancellationToken ct = default)
    {
        var me = CurrentUserId();

        if (recipientId == me)
            throw new ValidationException("You cannot start a conversation with yourself.");

        _ = await userRepository.GetByIdAsync(recipientId)
            ?? throw new NotFoundException("User not found.");

        // Get-or-create — same idempotent pattern as the profile module.
        var existing = await conversations.FindBetweenAsync(me, recipientId);
        if (existing != null)
            return await LoadSummaryAsync(existing.Id, me, ct);

        // Connected users can chat immediately; otherwise it's a pending message request.
        var connected = await conversations.AreConnectedAsync(me, recipientId, ct);
        var now = DateTime.UtcNow;

        var conversation = new Conversation
        {
            Id = Guid.NewGuid(),
            Status = connected ? ConversationStatus.Accepted : ConversationStatus.Pending,
            InitiatorId = me,
            CreatedAt = now
        };
        conversation.Participants.Add(new ConversationParticipant { ConversationId = conversation.Id, UserId = me, JoinedAt = now });
        conversation.Participants.Add(new ConversationParticipant { ConversationId = conversation.Id, UserId = recipientId, JoinedAt = now });

        await conversations.AddAsync(conversation);
        await conversations.SaveChangesAsync();

        logger.LogInformation(
            "Conversation started | Id: {ConversationId} | Initiator: {Initiator} | Recipient: {Recipient} | Status: {Status}",
            conversation.Id, me, recipientId, conversation.Status);

        // NOTE: the "message request received" push is deliberately NOT fired here — at this point
        // no message exists, so the recipient would get a request with an empty preview. It fires
        // in SendMessageAsync when the initiator sends the FIRST message into the pending thread.
        return await LoadSummaryAsync(conversation.Id, me, ct);
    }

    public async Task<ConversationSummaryDto> GetConversationAsync(Guid conversationId, CancellationToken ct = default)
    {
        var me = CurrentUserId();

        // Same existence + participant gate as GetMessagesAsync: unknown id → 404, outsider → 403.
        var conversation = await conversations.GetByIdAsync(conversationId)
            ?? throw new NotFoundException("Conversation not found.");

        if (!conversation.Participants.Any(p => p.UserId == me))
            throw new ForbiddenException("You are not a participant of this conversation.");

        // DELIBERATE: unlike GetAcceptedPageAsync/GetPendingRequestsPageAsync, we do NOT apply the
        // LastMessageAt != null filter here. A freshly created, message-less conversation must be
        // fetchable so the get-or-create navigation path (cold deep link, push-notification tap)
        // can resolve status and the other participant before any message exists.
        return await LoadSummaryAsync(conversationId, me, ct);
    }

    // ===== SEND =====

    public Task<MessageDto> SendMessageAsync(Guid conversationId, SendMessageRequestDto dto, CancellationToken ct = default)
        => SendCoreAsync(conversationId, dto.Body, dto.ReplyToMessageId, forwardedFromMessageId: null, ct);

    // The single write path for creating a message. Normal send, reply, and forward all funnel
    // through here, so the pending-request rule (c), implicit-accept, persist-then-notify, and
    // request-received push are enforced in EXACTLY one place — a forward can't sneak past rule (c).
    private async Task<MessageDto> SendCoreAsync(
        Guid conversationId, string body, Guid? replyToMessageId, Guid? forwardedFromMessageId, CancellationToken ct)
    {
        var me = CurrentUserId();

        var conversation = await conversations.GetByIdAsync(conversationId)
            ?? throw new NotFoundException("Conversation not found.");

        if (!conversation.Participants.Any(p => p.UserId == me))
            throw new ForbiddenException("You are not a participant of this conversation.");

        if (conversation.Status == ConversationStatus.Declined)
            throw new ForbiddenException("This conversation request was declined.");

        // A reply target must live in THIS conversation — a cross-conversation reply is a 400.
        // System messages (activity markers) also cannot be replied to.
        if (replyToMessageId.HasValue)
        {
            var replyTarget = await conversations.GetMessageByIdAsync(replyToMessageId.Value);
            if (replyTarget == null || replyTarget.ConversationId != conversationId)
                throw new ValidationException("You can only reply to a message in this conversation.");
            if (replyTarget.Type == MessageType.System)
                throw new ValidationException("System messages cannot be replied to.");
        }

        // True only when this send is the initiator's FIRST message into a pending thread —
        // i.e. the message that turns an empty pending conversation into an actual request.
        var isInitiatorsFirstRequestMessage = false;

        // True when the recipient's reply implicitly accepted a pending request in this send.
        var isImplicitAccept = false;

        if (conversation.Status == ConversationStatus.Pending)
        {
            if (conversation.InitiatorId == me)
            {
                // The initiator gets exactly one message until the recipient responds.
                var sentCount = await conversations.CountMessagesBySenderAsync(conversationId, me, ct);
                if (sentCount >= 1)
                    throw new ForbiddenException("Message request already sent — wait for the recipient to accept.");

                isInitiatorsFirstRequestMessage = true;
            }
            else
            {
                // The recipient replying implicitly accepts the request.
                conversation.Status = ConversationStatus.Accepted;
                conversation.RespondedAt = DateTime.UtcNow;
                isImplicitAccept = true;
            }
        }
        // Accepted → normal send (falls through).

        var now = DateTime.UtcNow;
        var message = new Message
        {
            Id = Guid.NewGuid(),
            ConversationId = conversationId,
            SenderId = me,
            Body = body.Trim(),
            Type = MessageType.Text,
            CreatedAt = now,
            ReplyToMessageId = replyToMessageId,
            ForwardedFromMessageId = forwardedFromMessageId
        };

        await conversations.AddMessageAsync(message);
        conversation.LastMessageAt = now;
        await conversations.SaveChangesAsync();   // persist FIRST — the message is durable before we notify

        var messageDto = new MessageDto
        {
            Id = message.Id,
            ConversationId = conversationId,
            SenderId = me,
            Body = message.Body,
            Type = message.Type,
            CreatedAt = now,
            IsDeleted = false,
            IsForwarded = forwardedFromMessageId != null
        };

        // A reply's `replyTo` needs a lookup to render for the OTHER participant — resolve it via the
        // projection (one query) only when this is actually a reply; plain sends keep the fast path.
        if (replyToMessageId != null)
            messageDto = await conversations.GetMessageDtoAsync(message.Id, me, ct) ?? messageDto;

        // Notify ALL participants including the sender (their other devices dedupe on message Id).
        var participantIds = conversation.Participants.Select(p => p.UserId).ToList();
        await SafeNotifyAsync(
            () => chatNotifier.MessageReceivedAsync(participantIds, messageDto, ct),
            conversationId);

        // A reply that implicitly accepted the request must tell the initiator the thread flipped
        // to Accepted — a bare MessageDto has no status field, so without this the initiator's
        // composer stays locked. Same event as the explicit AcceptAsync path; it is safe to receive
        // more than once — the client treats it idempotently ("set status = Accepted").
        if (isImplicitAccept)
        {
            await SafeNotifyAsync(
                () => chatNotifier.ConversationAcceptedAsync(conversation.InitiatorId, conversationId, ct),
                conversationId);
        }

        // The request now has content — push it to the recipient (only) so their requests list
        // updates in real time. Summary is loaded AFTER save so LastMessagePreview/LastMessageAt
        // are populated. Safe-wrapped: a notifier failure must not fail the durable send.
        if (isInitiatorsFirstRequestMessage)
        {
            var recipientId = conversation.Participants.First(p => p.UserId != me).UserId;
            var recipientView = await LoadSummaryAsync(conversationId, recipientId, ct);
            await SafeNotifyAsync(
                () => chatNotifier.ConversationRequestReceivedAsync(recipientId, recipientView, ct),
                conversationId);
        }

        return messageDto;
    }

    // ===== ACCEPT / DECLINE =====

    public async Task AcceptAsync(Guid conversationId, CancellationToken ct = default)
    {
        var conversation = await RespondToRequestAsync(conversationId, ConversationStatus.Accepted);

        // Tell the initiator their request went through (safe-wrapped).
        await SafeNotifyAsync(
            () => chatNotifier.ConversationAcceptedAsync(conversation.InitiatorId, conversationId, ct),
            conversationId);
    }

    public async Task DeclineAsync(Guid conversationId, CancellationToken ct = default)
    {
        await RespondToRequestAsync(conversationId, ConversationStatus.Declined);
        // No decline notification — declining stays silent to the initiator by design.
    }

    private async Task<Conversation> RespondToRequestAsync(Guid conversationId, ConversationStatus newStatus)
    {
        var me = CurrentUserId();

        var conversation = await conversations.GetByIdAsync(conversationId)
            ?? throw new NotFoundException("Conversation not found.");

        // Only the recipient (the non-initiator participant) may respond.
        var isParticipant = conversation.Participants.Any(p => p.UserId == me);
        if (!isParticipant || conversation.InitiatorId == me)
            throw new ForbiddenException("Only the recipient can respond to this request.");

        if (conversation.Status != ConversationStatus.Pending)
            throw new ConflictException("This request has already been responded to.");

        conversation.Status = newStatus;
        conversation.RespondedAt = DateTime.UtcNow;
        await conversations.SaveChangesAsync();

        logger.LogInformation(
            "Conversation request {Status} | Id: {ConversationId} | Recipient: {UserId}",
            newStatus, conversationId, me);

        return conversation;
    }

    // ===== LISTS =====

    public Task<PagedResult<ConversationSummaryDto>> GetConversationsAsync(int page, int pageSize, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        var (p, ps) = ClampPaging(page, pageSize);
        return conversations.GetAcceptedPageAsync(me, p, ps, ct);
    }

    public Task<PagedResult<ConversationSummaryDto>> GetRequestsAsync(int page, int pageSize, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        var (p, ps) = ClampPaging(page, pageSize);
        return conversations.GetPendingRequestsPageAsync(me, p, ps, ct);
    }

    // ===== MESSAGES (cursor) =====

    public async Task<MessagePageDto> GetMessagesAsync(Guid conversationId, DateTime? before, int limit, CancellationToken ct = default)
    {
        var me = CurrentUserId();

        var conversation = await conversations.GetByIdAsync(conversationId)
            ?? throw new NotFoundException("Conversation not found.");

        if (!conversation.Participants.Any(p => p.UserId == me))
            throw new ForbiddenException("You are not a participant of this conversation.");

        var take = ClampLimit(limit);

        // Fetch one extra row to know whether older messages remain (HasMore) without a COUNT.
        var fetched = await conversations.GetMessagesAsync(conversationId, me, before, take + 1, ct);
        var hasMore = fetched.Count > take;
        var items = (hasMore ? fetched.Take(take) : fetched).ToList();

        // Newest-first: the last item is the OLDEST returned — its timestamp is the next cursor.
        var nextCursor = items.Count > 0 ? items[^1].CreatedAt : (DateTime?)null;

        return new MessagePageDto
        {
            Items = items,
            NextCursor = nextCursor,
            HasMore = hasMore
        };
    }

    // ===== READ RECEIPT =====

    public async Task MarkReadAsync(Guid conversationId, CancellationToken ct = default)
    {
        var me = CurrentUserId();

        var conversation = await conversations.GetByIdAsync(conversationId)
            ?? throw new NotFoundException("Conversation not found.");

        var participant = conversation.Participants.FirstOrDefault(p => p.UserId == me)
            ?? throw new ForbiddenException("You are not a participant of this conversation.");

        participant.LastReadAt = DateTime.UtcNow;
        await conversations.SaveChangesAsync();
    }

    // ===== REACTIONS =====

    public async Task<IReadOnlyList<MessageReactionSummaryDto>> ReactAsync(
        Guid conversationId, Guid messageId, string emoji, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        var conversation = await ParticipantConversationAsync(conversationId, me);
        var reactTarget = await MessageInConversationAsync(conversationId, messageId);
        if (reactTarget.Type == MessageType.System)
            throw new ValidationException("System messages cannot be reacted to.");

        // One reaction per user per message. WhatsApp toggle semantics:
        //   - no existing reaction        → add it
        //   - existing, SAME emoji        → remove it (tapping 👍 again clears your 👍 — the gesture a
        //                                    user reaches for first; without this there is no way to
        //                                    clear a reaction from the reaction bar via PUT)
        //   - existing, DIFFERENT emoji   → replace in place (still one row per user)
        // The explicit DELETE .../reaction endpoint (RemoveReactionAsync) remains regardless — this
        // toggle is a convenience on PUT, not a replacement for it.
        var existing = await conversations.GetReactionAsync(messageId, me);
        if (existing == null)
            await conversations.AddReactionAsync(new MessageReaction
            {
                MessageId = messageId,
                UserId = me,
                Emoji = emoji,
                CreatedAt = DateTime.UtcNow
            });
        else if (existing.Emoji == emoji)
            await conversations.RemoveReactionAsync(existing);
        else
            existing.Emoji = emoji;

        await conversations.SaveChangesAsync();
        return await NotifyReactionChangedAsync(conversation, messageId, me, ct);
    }

    public async Task RemoveReactionAsync(Guid conversationId, Guid messageId, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        var conversation = await ParticipantConversationAsync(conversationId, me);
        await MessageInConversationAsync(conversationId, messageId);

        // Idempotent — removing a reaction that isn't there is a no-op, not an error.
        var existing = await conversations.GetReactionAsync(messageId, me);
        if (existing != null)
        {
            await conversations.RemoveReactionAsync(existing);
            await conversations.SaveChangesAsync();
        }

        await NotifyReactionChangedAsync(conversation, messageId, me, ct);
    }

    // Fans out the ReactionChanged event (aggregate only — ReactedByMe stripped, it's caller-relative)
    // and returns the caller-relative summary for the HTTP response. One summary query total.
    private async Task<IReadOnlyList<MessageReactionSummaryDto>> NotifyReactionChangedAsync(
        Conversation conversation, Guid messageId, Guid me, CancellationToken ct)
    {
        var callerView = await conversations.GetReactionSummaryAsync(messageId, me, ct);
        var eventView = callerView
            .Select(r => new MessageReactionSummaryDto { Emoji = r.Emoji, Count = r.Count, ReactedByMe = false })
            .ToList();

        var participantIds = conversation.Participants.Select(p => p.UserId).ToList();
        await SafeNotifyAsync(
            () => chatNotifier.ReactionChangedAsync(participantIds, conversation.Id, messageId, eventView, ct),
            conversation.Id);

        return callerView;
    }

    // ===== EDIT =====

    public async Task<MessageDto> EditMessageAsync(Guid conversationId, Guid messageId, string body, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        var conversation = await ParticipantConversationAsync(conversationId, me);
        var message = await MessageInConversationAsync(conversationId, messageId);

        if (message.Type == MessageType.System)
            throw new ValidationException("System messages cannot be edited.");
        if (message.SenderId != me)
            throw new ForbiddenException("You can only edit your own messages.");
        if (message.DeletedAt != null)
            throw new ForbiddenException("You cannot edit a deleted message.");
        // Server-enforced window — a client clock could otherwise bypass it.
        if (DateTime.UtcNow - message.CreatedAt > EditWindow)
            throw new ForbiddenException("The edit window for this message has passed.");

        message.Body = body.Trim();
        message.EditedAt = DateTime.UtcNow;
        await conversations.SaveChangesAsync();

        var dto = await conversations.GetMessageDtoAsync(messageId, me, ct)
            ?? throw new NotFoundException("Message not found.");

        var participantIds = conversation.Participants.Select(p => p.UserId).ToList();
        await SafeNotifyAsync(() => chatNotifier.MessageEditedAsync(participantIds, dto, ct), conversationId);
        return dto;
    }

    // ===== PIN =====

    public async Task PinAsync(Guid conversationId, Guid messageId, PinMessageRequestDto dto, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        var conversation = await ParticipantConversationAsync(conversationId, me);
        var message = await MessageInConversationAsync(conversationId, messageId);

        if (message.Type == MessageType.System)
            throw new ValidationException("System messages cannot be pinned.");

        var now = DateTime.UtcNow;
        var expiresAt = ComputePinExpiry(now, dto.Duration);
        var isActivelyPinned = message.PinnedAt != null &&
                               (message.PinExpiresAt == null || message.PinExpiresAt > now);

        if (isActivelyPinned)
        {
            // Duration change on an already-active pin: update expiry without consuming cap.
            // No system message — the pin itself didn't change, just its duration.
            message.PinnedAt = now;
            message.PinnedByUserId = me;
            message.PinExpiresAt = expiresAt;
            await conversations.SaveChangesAsync();

            var pIds = conversation.Participants.Select(p => p.UserId).ToList();
            await SafeNotifyAsync(
                () => chatNotifier.MessagePinChangedAsync(pIds, conversationId, messageId, true, expiresAt, ct),
                conversationId);
            return;
        }

        // New pin (first pin or re-pin after expiry). Cap check on active pins only.
        var activeCount = await conversations.CountPinnedAsync(conversationId, ct);

        if (activeCount >= MaxPinnedPerConversation)
        {
            if (!dto.ReplaceOldest)
                throw new ConflictException(
                    $"Pin limit reached — a conversation can have at most {MaxPinnedPerConversation} pinned messages.");

            // Replace-oldest: all three writes (unpin old, pin new, two system messages) in ONE
            // SaveChangesAsync so a partial failure cannot leave the conversation with a phantom unpin.
            var oldest = await conversations.GetOldestActivePinAsync(conversationId, ct)
                ?? throw new ConflictException(
                    $"Pin limit reached — a conversation can have at most {MaxPinnedPerConversation} pinned messages.");

            oldest.PinnedAt = null;
            oldest.PinnedByUserId = null;
            oldest.PinExpiresAt = null;

            message.PinnedAt = now;
            message.PinnedByUserId = me;
            message.PinExpiresAt = expiresAt;

            var unpinSys = BuildSystemMessage(conversationId, me, Domain.Enums.SystemEventType.MessageUnpinned, oldest.Id, now);
            var pinSys   = BuildSystemMessage(conversationId, me, Domain.Enums.SystemEventType.MessagePinned, messageId, now.AddTicks(1));
            await conversations.AddMessageAsync(unpinSys);
            await conversations.AddMessageAsync(pinSys);
            conversation.LastMessageAt = pinSys.CreatedAt;
            await conversations.SaveChangesAsync();  // atomic

            var participantIds = conversation.Participants.Select(p => p.UserId).ToList();
            await SafeNotifyAsync(
                () => chatNotifier.MessagePinChangedAsync(participantIds, conversationId, oldest.Id, false, null, ct),
                conversationId);
            await SafeNotifyAsync(
                () => chatNotifier.MessagePinChangedAsync(participantIds, conversationId, messageId, true, expiresAt, ct),
                conversationId);
            await SafeNotifyAsync(
                () => chatNotifier.MessageReceivedAsync(participantIds, SystemMsgToDto(unpinSys), ct),
                conversationId);
            await SafeNotifyAsync(
                () => chatNotifier.MessageReceivedAsync(participantIds, SystemMsgToDto(pinSys), ct),
                conversationId);
            return;
        }

        // Normal pin — cap not hit.
        message.PinnedAt = now;
        message.PinnedByUserId = me;
        message.PinExpiresAt = expiresAt;

        var sysMsg = BuildSystemMessage(conversationId, me, Domain.Enums.SystemEventType.MessagePinned, messageId, now);
        await conversations.AddMessageAsync(sysMsg);
        conversation.LastMessageAt = now;
        await conversations.SaveChangesAsync();

        var pIdsNormal = conversation.Participants.Select(p => p.UserId).ToList();
        await SafeNotifyAsync(
            () => chatNotifier.MessagePinChangedAsync(pIdsNormal, conversationId, messageId, true, expiresAt, ct),
            conversationId);
        await SafeNotifyAsync(
            () => chatNotifier.MessageReceivedAsync(pIdsNormal, SystemMsgToDto(sysMsg), ct),
            conversationId);
    }

    public async Task UnpinAsync(Guid conversationId, Guid messageId, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        var conversation = await ParticipantConversationAsync(conversationId, me);
        var message = await MessageInConversationAsync(conversationId, messageId);

        if (message.PinnedAt == null) return;   // not pinned — idempotent no-op

        var now = DateTime.UtcNow;
        message.PinnedAt = null;
        message.PinnedByUserId = null;
        message.PinExpiresAt = null;

        var sysMsg = BuildSystemMessage(conversationId, me, Domain.Enums.SystemEventType.MessageUnpinned, messageId, now);
        await conversations.AddMessageAsync(sysMsg);
        conversation.LastMessageAt = now;
        await conversations.SaveChangesAsync();

        var participantIds = conversation.Participants.Select(p => p.UserId).ToList();
        await SafeNotifyAsync(
            () => chatNotifier.MessagePinChangedAsync(participantIds, conversationId, messageId, false, null, ct),
            conversationId);
        await SafeNotifyAsync(
            () => chatNotifier.MessageReceivedAsync(participantIds, SystemMsgToDto(sysMsg), ct),
            conversationId);
    }

    public async Task<IReadOnlyList<MessageDto>> GetPinnedAsync(Guid conversationId, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        await ParticipantConversationAsync(conversationId, me);
        return await conversations.GetPinnedAsync(conversationId, me, ct);
    }

    // ===== DELETE (two kinds) =====

    public async Task DeleteForEveryoneAsync(Guid conversationId, Guid messageId, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        var conversation = await ParticipantConversationAsync(conversationId, me);
        var message = await MessageInConversationAsync(conversationId, messageId);

        if (message.Type == MessageType.System)
            throw new ForbiddenException("System messages cannot be deleted for everyone.");
        // Own messages only — a non-owner is refused even on an already-deleted row.
        if (message.SenderId != me)
            throw new ForbiddenException("You can only delete your own messages for everyone.");
        if (message.DeletedAt != null) return;   // idempotent — already a shared tombstone
        // Server-enforced window.
        if (DateTime.UtcNow - message.CreatedAt > DeleteForEveryoneWindow)
            throw new ForbiddenException("The delete-for-everyone window for this message has passed.");

        message.DeletedAt = DateTime.UtcNow;   // shared tombstone — both users see "message deleted"
        await conversations.SaveChangesAsync();

        var participantIds = conversation.Participants.Select(p => p.UserId).ToList();
        await SafeNotifyAsync(
            () => chatNotifier.MessageDeletedAsync(participantIds, conversationId, messageId, ct),
            conversationId);
    }

    public async Task DeleteForMeAsync(Guid conversationId, Guid messageId, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        await ParticipantConversationAsync(conversationId, me);
        await MessageInConversationAsync(conversationId, messageId);   // any visible message, own or not

        // Idempotent — a per-user tombstone that already exists is a no-op.
        if (await conversations.HasMessageDeletionAsync(messageId, me, ct)) return;

        await conversations.AddMessageDeletionAsync(new MessageDeletion
        {
            MessageId = messageId,
            UserId = me,
            DeletedAt = DateTime.UtcNow
        });
        await conversations.SaveChangesAsync();

        // DELIBERATELY no realtime event — a delete-for-me is private to this user. Firing it would
        // leak one participant's private deletion to the other.
    }

    // ===== FORWARD =====

    public async Task<IReadOnlyList<MessageDto>> ForwardAsync(
        Guid sourceConversationId, ForwardMessagesRequestDto dto, CancellationToken ct = default)
    {
        var me = CurrentUserId();

        // Participant in BOTH source and target (clean 403 before any write). The target gate is
        // re-checked inside SendCoreAsync, which is also where rule (c) applies to the target.
        await ParticipantConversationAsync(sourceConversationId, me);
        var target = await ParticipantConversationAsync(dto.TargetConversationId, me);

        // ── PRE-FLIGHT (atomic): validate the WHOLE batch before writing anything ──────────────────
        // A forward loops SendCoreAsync per message. Without this gate, a refusal in position N (a bad
        // id, or rule (c) tripping on message 2) would leave messages 1..N-1 already delivered — a
        // silent partial forward: the caller sees an error and believes nothing was sent while the
        // recipient sees some of it. Either the whole batch delivers or none of it does.

        // 1) Every selected id must exist in the source thread and be live (not a tombstone). Resolve
        //    all of them up front so a bad id in ANY position refuses the batch before the first send.
        var sourceMessages = await conversations.GetMessagesByIdsAsync(sourceConversationId, dto.MessageIds, ct);
        var byId = sourceMessages.ToDictionary(m => m.Id);
        foreach (var id in dto.MessageIds)
        {
            if (!byId.TryGetValue(id, out var src))
                throw new NotFoundException("Message not found in source conversation.");
            if (src.DeletedAt != null)
                throw new ValidationException("You cannot forward a deleted message.");
            if (src.Type == MessageType.System)
                throw new ValidationException("System messages cannot be forwarded.");
        }

        // 2) Rule (c) must permit the ENTIRE batch. Reads the SAME state SendCoreAsync reads (target
        //    status, initiator, caller's sent count) — an additional gate, not a duplicated policy. A
        //    pending request grants the initiator exactly ONE message until the recipient responds; a
        //    batch larger than the remaining allowance is refused whole (rather than delivering part of
        //    it and 403-ing the rest). Accepted targets have no limit; a recipient forwarding into a
        //    pending thread implicitly accepts on the first message, so no cap applies to them either.
        if (target.Status == ConversationStatus.Pending && target.InitiatorId == me)
        {
            var alreadySent = await conversations.CountMessagesBySenderAsync(dto.TargetConversationId, me, ct);
            var remainingAllowance = Math.Max(0, 1 - alreadySent);
            if (dto.MessageIds.Count > remainingAllowance)
                throw new ForbiddenException(
                    "A message request permits only one message — multiple messages cannot be forwarded until the recipient accepts.");
        }

        // ── COMMIT ─────────────────────────────────────────────────────────────────────────────────
        // All checks passed. Write through the single send path in the caller's selection order. Rule
        // (c) still runs inside SendCoreAsync (defence in depth); the pre-flight guarantees it won't trip.
        var results = new List<MessageDto>(dto.MessageIds.Count);
        foreach (var id in dto.MessageIds)   // preserve the caller's selection order
        {
            var src = byId[id];
            var forwarded = await SendCoreAsync(
                dto.TargetConversationId, src.Body, replyToMessageId: null, forwardedFromMessageId: src.Id, ct);
            results.Add(forwarded);
        }

        return results;
    }

    // ===== HELPERS =====

    private Guid CurrentUserId() =>
        currentUser.UserId ?? throw new UnauthorizedException("Not authenticated.");

    // Load a conversation and gate on participation: unknown id → 404, outsider → 403.
    private async Task<Conversation> ParticipantConversationAsync(Guid conversationId, Guid me)
    {
        var conversation = await conversations.GetByIdAsync(conversationId)
            ?? throw new NotFoundException("Conversation not found.");
        if (!conversation.Participants.Any(p => p.UserId == me))
            throw new ForbiddenException("You are not a participant of this conversation.");
        return conversation;
    }

    // Load a message and confirm it belongs to the conversation. A cross-conversation id is treated
    // as 404 (don't leak that a message exists in some other thread).
    private async Task<Message> MessageInConversationAsync(Guid conversationId, Guid messageId)
    {
        var message = await conversations.GetMessageByIdAsync(messageId);
        if (message == null || message.ConversationId != conversationId)
            throw new NotFoundException("Message not found.");
        return message;
    }

    private async Task<ConversationSummaryDto> LoadSummaryAsync(Guid conversationId, Guid userId, CancellationToken ct) =>
        await conversations.GetSummaryByIdAsync(conversationId, userId, ct)
            ?? throw new NotFoundException("Conversation not found.");

    // Clamp (not reject) — mirrors PeopleService so no caller can pull a whole table.
    private static (int page, int pageSize) ClampPaging(int page, int pageSize)
    {
        var p = page < 1 ? 1 : page;
        var ps = pageSize < 1 ? DefaultPageSize
               : pageSize > MaxPageSize ? MaxPageSize
               : pageSize;
        return (p, ps);
    }

    private static int ClampLimit(int limit) =>
        limit < 1 ? DefaultMessageLimit
      : limit > MaxMessageLimit ? MaxMessageLimit
      : limit;

    // Persist-then-notify: the message/row is already durable, so a transport failure must not
    // fail the request. Log a warning; a client refetch recovers the missed event.
    private async Task SafeNotifyAsync(Func<Task> notify, Guid conversationId)
    {
        try
        {
            await notify();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex,
                "Chat notification failed for conversation {ConversationId}; state is persisted and will be recovered on client refetch.",
                conversationId);
        }
    }

    // Compute the absolute UTC expiry for a new pin. Stored as a timestamp, not as a duration value,
    // so the intent is unambiguous even if duration enum values are later adjusted.
    private static DateTime ComputePinExpiry(DateTime now, PinDuration duration) => duration switch
    {
        PinDuration.TwentyFourHours => now + PinWindow24Hours,
        PinDuration.SevenDays       => now + PinWindow7Days,
        PinDuration.ThirtyDays      => now + PinWindow30Days,
        _ => throw new ValidationException($"Unknown pin duration: {duration}.")
    };

    private static Message BuildSystemMessage(
        Guid conversationId, Guid actorId, Domain.Enums.SystemEventType eventType, Guid targetMessageId, DateTime at) =>
        new()
        {
            Id = Guid.NewGuid(),
            ConversationId = conversationId,
            SenderId = actorId,
            Body = string.Empty,
            Type = MessageType.System,
            SystemEventType = eventType,
            SystemTargetMessageId = targetMessageId,
            CreatedAt = at
        };

    // Minimal DTO for a system message fan-out (no reactions, no reply, no forward).
    private static MessageDto SystemMsgToDto(Message msg) => new()
    {
        Id = msg.Id,
        ConversationId = msg.ConversationId,
        SenderId = msg.SenderId,
        Body = string.Empty,
        Type = msg.Type,
        CreatedAt = msg.CreatedAt,
        IsDeleted = false,
        SystemEventType = msg.SystemEventType,
        SystemTargetMessageId = msg.SystemTargetMessageId
    };
}
