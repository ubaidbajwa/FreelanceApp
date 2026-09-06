using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Messaging.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging;
using System.Text;

namespace FreelanceApp.Application.Features.Messaging.Services;

public class ChatService(
    IConversationRepository conversations,
    IUserRepository userRepository,
    IChatNotifier chatNotifier,
    ICurrentUserService currentUser,
    IMediaStorageService mediaStorage,
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

    // ===== Media limits (M-M4) — server-enforced; a client-side limit is only a suggestion =====
    public const long MaxImageBytes = 10L * 1024 * 1024;   // 10 MB
    public const long MaxVideoBytes = 50L * 1024 * 1024;   // 50 MB
    public const int  MaxVideoDurationSeconds = 120;
    public const int  MaxVideoDurationMs = MaxVideoDurationSeconds * 1000;

    // ===== Voice limits (M-M6) — same server-enforced discipline as image/video =====
    public const long MaxAudioBytes = 10L * 1024 * 1024;   // 10 MB
    public const int  MaxAudioDurationSeconds = 300;       // five minutes
    public const int  MaxAudioDurationMs = MaxAudioDurationSeconds * 1000;

    // ===== Document limits (M-M8) — a document is stored and served, never parsed or executed =====
    // 25 MB: uploads pass THROUGH the API (ADR 0004 §7i), so each upload holds a request thread for its
    // duration — a large cap multiplies that across concurrent users. On a mobile link 25 MB is already
    // a slow upload; a higher cap makes failure likelier, not the feature more capable. It also bounds
    // the damage from an abusive client, alongside the per-user media rate limit.
    public const long MaxDocumentBytes = 25L * 1024 * 1024;   // 25 MB

    // Bounded content window for the txt/csv heuristic — read at most the first 8 KB, never the whole file.
    private const int DocumentTextSniffBytes = 8192;

    // Waveform: at most 64 amplitude samples (plenty of resolution for a bubble a few cm wide, and it
    // bounds the column). A client must not push thousands of points.
    public const int MaxWaveformSamples = 64;

    // Optional media caption cap — same 4000 as a text body (it is stored in Body, a varchar(4000)).
    public const int MaxCaptionLength = 4000;

    // Validate the ACTUAL content type, not the extension — a .jpg on an arbitrary payload is trivial
    // to fake, so these gate both the declared MIME and the magic bytes below.
    public static readonly IReadOnlySet<string> AllowedImageTypes =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "image/jpeg", "image/png", "image/webp", "image/gif" };
    public static readonly IReadOnlySet<string> AllowedVideoTypes =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "video/mp4", "video/webm", "video/quicktime" };
    // Voice (M-M6): what mobile recorders actually produce — m4a/aac on iOS, opus/m4a on Android.
    public static readonly IReadOnlySet<string> AllowedAudioTypes =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "audio/mp4", "audio/aac", "audio/ogg", "audio/webm" };

    // Document allowlist (M-M8). ALLOWLIST ONLY — anything not listed here is rejected. A blocklist of
    // "dangerous" extensions is deliberately NOT the primary control: a blocklist is the set of things we
    // happened to think of, and the attacker's job is to find one we didn't; an allowlist inverts that
    // burden. .zip is deliberately excluded — a zip is a container that can hold anything, so allowing it
    // would make the whole allowlist meaningless (inspecting the contents means unzipping, which we refuse
    // — that is how zip bombs work). See ADR 0004 §10. Each entry maps an extension to the ONE declared
    // MIME consistent with it, and the family whose magic-byte signature the bytes must match.
    private enum DocumentFamily { Pdf, Ooxml, Ole2, Text }

    private static readonly IReadOnlyDictionary<string, (string Mime, DocumentFamily Family)> AllowedDocuments =
        new Dictionary<string, (string, DocumentFamily)>(StringComparer.OrdinalIgnoreCase)
        {
            [".pdf"]  = ("application/pdf", DocumentFamily.Pdf),
            [".docx"] = ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", DocumentFamily.Ooxml),
            [".xlsx"] = ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", DocumentFamily.Ooxml),
            [".pptx"] = ("application/vnd.openxmlformats-officedocument.presentationml.presentation", DocumentFamily.Ooxml),
            [".doc"]  = ("application/msword", DocumentFamily.Ole2),
            [".xls"]  = ("application/vnd.ms-excel", DocumentFamily.Ole2),
            [".ppt"]  = ("application/vnd.ms-powerpoint", DocumentFamily.Ole2),
            [".txt"]  = ("text/plain", DocumentFamily.Text),
            [".csv"]  = ("text/csv", DocumentFamily.Text),
        };

    // Cloudinary folder for chat media (kept separate from KYC / profile-photo folders).
    private const string MediaFolder = "skillora/chat";

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
        => SendCoreAsync(conversationId, dto.Body, dto.ReplyToMessageId, forwardedFromMessageId: null, mediaFactory: null, ct);

    public async Task<MessageDto> SendMediaMessageAsync(
        Guid conversationId, SendMediaMessageRequestDto request, MediaUploadInput file, CancellationToken ct = default)
    {
        // 1) Validate the file LOCALLY first — type, size, and magic bytes — so a bad file never reaches
        //    Cloudinary. Throws 400 naming the specific limit that was hit.
        var (kind, documentFileName) = await ValidateAndDetectMediaAsync(file, ct);

        // 1b) Validate the waveform SHAPE up front (before any upload) — a malformed value is a 400 and
        //     must never cost a Cloudinary round-trip. Only carried onto a voice note (see UploadMediaAsync).
        var waveform = ValidateWaveform(request.Waveform);

        // 1c) Caption is OPTIONAL for media, but when present it is bounded to the same 4000 as a text
        //     body (it is stored in Body, a varchar(4000)). Enforced HERE, not in a validator: the
        //     multipart endpoint binds SendMediaMessageApiRequest, so FluentValidation auto-validation
        //     never ran the DTO validator — without this an over-long caption overflowed the column and
        //     surfaced as a 500 at SaveChanges instead of a clean 400.
        var caption = request.Caption?.Trim() ?? string.Empty;
        if (caption.Length > MaxCaptionLength)
            throw new ValidationException($"Caption is too long — the maximum is {MaxCaptionLength} characters.");

        // 2) Route through SendCoreAsync with a DEFERRED upload. The upload runs only after the
        //    participant / declined / rule-(c) gates pass inside SendCoreAsync, so an unauthorized send
        //    never uploads — "a file exists only if a message exists". Caption is the (optional) body.
        return await SendCoreAsync(
            conversationId, caption, request.ReplyToMessageId, forwardedFromMessageId: null,
            mediaFactory: innerCt => UploadMediaAsync(kind, file, waveform, documentFileName, innerCt), ct);
    }

    // The single write path for creating a message. Normal send, reply, and forward all funnel
    // through here, so the pending-request rule (c), implicit-accept, persist-then-notify, and
    // request-received push are enforced in EXACTLY one place — a forward can't sneak past rule (c).
    private async Task<MessageDto> SendCoreAsync(
        Guid conversationId, string body, Guid? replyToMessageId, Guid? forwardedFromMessageId,
        Func<CancellationToken, Task<MediaMessagePayload>>? mediaFactory, CancellationToken ct)
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

        // All gates passed. If this is a media send, upload NOW (deferred until here so an unauthorized
        // send never touches Cloudinary). For a forward the factory just returns the SOURCE's media —
        // no re-upload; the forwarded copy references the same asset (same MediaUrl + MediaPublicId).
        MediaMessagePayload? media = mediaFactory is null ? null : await mediaFactory(ct);

        var now = DateTime.UtcNow;
        var message = new Message
        {
            Id = Guid.NewGuid(),
            ConversationId = conversationId,
            SenderId = me,
            Body = body.Trim(),   // caption for media (may be empty); required non-empty for text at the DTO
            Type = media?.Type ?? MessageType.Text,
            CreatedAt = now,
            ReplyToMessageId = replyToMessageId,
            ForwardedFromMessageId = forwardedFromMessageId,
            MediaUrl = media?.MediaUrl,
            MediaThumbnailUrl = media?.MediaThumbnailUrl,
            MediaWidth = media?.MediaWidth,
            MediaHeight = media?.MediaHeight,
            MediaDurationMs = media?.MediaDurationMs,
            MediaSizeBytes = media?.MediaSizeBytes,
            MediaMimeType = media?.MediaMimeType,
            MediaPublicId = media?.MediaPublicId,
            MediaWaveform = media?.MediaWaveform,
            MediaFileName = media?.MediaFileName
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
            IsForwarded = forwardedFromMessageId != null,
            MediaUrl = media?.MediaUrl,
            MediaThumbnailUrl = media?.MediaThumbnailUrl,
            MediaWidth = media?.MediaWidth,
            MediaHeight = media?.MediaHeight,
            MediaDurationMs = media?.MediaDurationMs,
            MediaMimeType = media?.MediaMimeType,
            MediaWaveform = media?.MediaWaveform,
            MediaFileName = media?.MediaFileName
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

        var previousReadAt = participant.LastReadAt;
        var now = DateTime.UtcNow;
        participant.LastReadAt = now;
        await conversations.SaveChangesAsync();   // persist FIRST — the watermark is durable before we notify

        // Notify the OTHER participant so their sent bubbles flip to the read tick — but only when this
        // read actually advanced past unread activity. "Moved forward" is measured against the
        // conversation's last activity: if I had already read up to (or past) LastMessageAt, a debounced
        // re-mark reports nothing new, so a ConversationRead event would be pure noise — suppress it.
        // (LastMessageAt is null only for a message-less thread, where there is nothing to have read.)
        var lastActivity = conversation.LastMessageAt;
        var movedForward = lastActivity.HasValue &&
                           (previousReadAt == null || previousReadAt.Value < lastActivity.Value);
        if (!movedForward)
            return;

        var otherId = conversation.Participants.First(p => p.UserId != me).UserId;
        await SafeNotifyAsync(
            () => chatNotifier.ConversationReadAsync(otherId, conversationId, now, ct),
            conversationId);
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
        // The 15-minute edit window is text-only — media (image/video/voice) messages cannot be edited.
        // Editing a caption is out of scope for this slice; a voice note has no editable text at all.
        if (message.Type is MessageType.Image or MessageType.Video or MessageType.Voice or MessageType.File)
            throw new ValidationException("Media messages cannot be edited.");
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
            // A forwarded media message REUSES the source's asset (same MediaUrl + MediaPublicId) — a
            // forward is a reference, not a copy, so there is no re-upload. This shared public id is
            // exactly why delete-for-everyone must not delete the Cloudinary asset (see docs/TODO.md).
            Func<CancellationToken, Task<MediaMessagePayload>>? mediaFactory =
                src.Type is MessageType.Image or MessageType.Video or MessageType.Voice or MessageType.File
                    ? _ => Task.FromResult(MediaMessagePayload.FromMessage(src))
                    : null;
            var forwarded = await SendCoreAsync(
                dto.TargetConversationId, src.Body, replyToMessageId: null, forwardedFromMessageId: src.Id,
                mediaFactory, ct);
            results.Add(forwarded);
        }

        return results;
    }

    // ===== VOICE "PLAYED" RECEIPT (M-M7) =====

    public async Task MarkPlayedAsync(Guid conversationId, Guid messageId, CancellationToken ct = default)
    {
        var me = CurrentUserId();
        await ParticipantConversationAsync(conversationId, me);   // 404 unknown conversation / 403 outsider
        var message = await MessageInConversationAsync(conversationId, messageId);   // 404 unknown message

        // Only a voice note can be "played" — marking a text/image/video played is meaningless, and
        // rejecting it surfaces a client bug instead of silently storing nonsense.
        if (message.Type != MessageType.Voice)
            throw new ValidationException("Only voice notes can be marked as played.");
        // You do not record playing your OWN note — allowing it would let a sender manufacture their
        // own played receipt.
        if (message.SenderId == me)
            throw new ValidationException("You cannot mark your own voice note as played.");
        // A played receipt on a deleted note is meaningless.
        if (message.DeletedAt != null)
            throw new ValidationException("You cannot mark a deleted message as played.");

        // Idempotent — the record already exists ⇒ no-op AND no event. The insert either happened or it
        // did not; branching on the prior existence is exactly how we avoid pushing a duplicate event.
        if (await conversations.HasMessagePlayAsync(messageId, me, ct))
            return;

        await conversations.AddMessagePlayAsync(new MessagePlay
        {
            MessageId = messageId,
            UserId = me,
            PlayedAt = DateTime.UtcNow
        });
        await conversations.SaveChangesAsync();   // persist FIRST — durable before we notify

        // The SENDER's bubble is the one that changes — notify them only. Safe-wrapped: a notifier
        // failure logs a warning and does not fail the request (the record is already durable).
        await SafeNotifyAsync(
            () => chatNotifier.MessagePlayedAsync(message.SenderId, conversationId, messageId, ct),
            conversationId);
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

    // ===== MEDIA HELPERS (M-M4) =====

    // Validate a media file BEFORE any upload: declared type must be allowed, size within the per-kind
    // limit, and the leading magic bytes must match the declared type (a spoofed extension can't pass).
    // A rejection names the specific limit that was hit. Returns which kind the file is.
    private async Task<(MediaKind Kind, string? FileName)> ValidateAndDetectMediaAsync(MediaUploadInput file, CancellationToken ct)
    {
        // Image/video/audio are keyed on the declared MIME (as in M-M4/M-M6). A document is keyed on its
        // EXTENSION instead — a document's name is content, and the allowlist is per-extension — so any
        // file whose declared MIME is not an image/video/audio type is routed to the document path below.
        MediaKind kind;
        long maxBytes;
        string maxLabel;
        if (AllowedImageTypes.Contains(file.ContentType)) { kind = MediaKind.Image; maxBytes = MaxImageBytes; maxLabel = "10 MB"; }
        else if (AllowedVideoTypes.Contains(file.ContentType)) { kind = MediaKind.Video; maxBytes = MaxVideoBytes; maxLabel = "50 MB"; }
        else if (AllowedAudioTypes.Contains(file.ContentType)) { kind = MediaKind.Audio; maxBytes = MaxAudioBytes; maxLabel = "10 MB"; }
        else
            return await ValidateDocumentAsync(file, ct);

        if (file.Length <= 0)
            throw new ValidationException("The uploaded file is empty.");
        if (file.Length > maxBytes)
            throw new ValidationException(
                $"File is too large — the maximum for {kind switch { MediaKind.Image => "images", MediaKind.Video => "videos", _ => "voice notes" }} is {maxLabel}.");

        // Magic-byte check — verify the ACTUAL content, not the trivially-spoofable extension/declared type.
        if (!file.Content.CanSeek)
            throw new ValidationException("The uploaded file could not be read.");
        var header = new byte[12];
        file.Content.Seek(0, SeekOrigin.Begin);
        var read = await ReadUpToAsync(file.Content, header, ct);
        file.Content.Seek(0, SeekOrigin.Begin);   // rewind so the upload reads the whole stream from 0
        if (!MagicBytesMatch(file.ContentType, header, read))
            throw new ValidationException("The file content does not match its declared type.");

        return (kind, null);
    }

    // Validate a document across THREE layers, none sufficient alone (see ADR 0004 §10). Every check is
    // local, so a rejected document never reaches Cloudinary — there is no upload-then-delete for a
    // document (unlike video/voice duration, which is only knowable after upload). Every rejection is a
    // 400 naming the specific failure and is logged at warning level with user/mime/ext/size/reason.
    // Returns the SANITISED filename to store alongside MediaKind.Document.
    private async Task<(MediaKind Kind, string? FileName)> ValidateDocumentAsync(MediaUploadInput file, CancellationToken ct)
    {
        // ── Layer 1: extension — the weakest, fully attacker-controlled signal. Allowlist only. ──────
        var ext = Path.GetExtension(file.FileName ?? string.Empty).ToLowerInvariant();
        if (string.IsNullOrEmpty(ext) || !AllowedDocuments.TryGetValue(ext, out var spec))
            throw RejectDocument(file, ext,
                $"Unsupported file type '{(string.IsNullOrEmpty(ext) ? file.ContentType : ext)}'. Allowed: PDF, Word (.doc/.docx), Excel (.xls/.xlsx), PowerPoint (.ppt/.pptx), text (.txt) and CSV (.csv).",
                "extension not on allowlist");

        // ── Layer 2: declared MIME — also client-supplied and forgeable. Must be consistent with the
        //    extension (a .pdf declared text/plain is rejected regardless of its bytes). ───────────────
        if (!string.Equals(file.ContentType, spec.Mime, StringComparison.OrdinalIgnoreCase))
            throw RejectDocument(file, ext,
                $"The declared type '{file.ContentType}' is inconsistent with the file extension '{ext}'.",
                "declared MIME inconsistent with extension");

        // Size — checked against the DECLARED content length BEFORE reading the file, so a 500 MB upload
        // is rejected early rather than buffered only to discover it is too large (that is the attack).
        if (file.Length <= 0)
            throw RejectDocument(file, ext, "The uploaded file is empty.", "empty file");
        if (file.Length > MaxDocumentBytes)
            throw RejectDocument(file, ext, "File is too large — the maximum for documents is 25 MB.", "over size limit");

        // ── Layer 3: magic bytes — place the file in the FAMILY the extension implies. This is the
        //    strongest guarantee available without opening the container: docx/xlsx/pptx are all zips and
        //    share one signature, doc/xls/ppt are all OLE2 and share another, so bytes can confirm the
        //    family but never the specific document type. We deliberately do NOT unzip to inspect
        //    [Content_Types].xml — decompressing hostile archives is how zip bombs work. ────────────────
        if (!file.Content.CanSeek)
            throw RejectDocument(file, ext, "The uploaded file could not be read.", "stream not seekable");

        var buffer = new byte[DocumentTextSniffBytes];   // at most 8 KB — covers both magic bytes and the text sniff
        file.Content.Seek(0, SeekOrigin.Begin);
        var read = await ReadUpToAsync(file.Content, buffer, ct);
        file.Content.Seek(0, SeekOrigin.Begin);          // rewind so the upload reads the whole stream from 0

        // Attack signal: a rejected upload that carries a known-executable signature is a probable probe,
        // not an innocent wrong-file — worth being able to find later. Logged only; the rejection itself
        // always comes from FAILING the allowlist/family check below, never from matching this list.
        var exeSignature = DetectExecutableSignature(buffer, read);

        var familyOk = spec.Family switch
        {
            DocumentFamily.Pdf  => StartsWith(buffer, read, 0x25, 0x50, 0x44, 0x46, 0x2D),               // %PDF-
            DocumentFamily.Ole2 => StartsWith(buffer, read, 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1),
            DocumentFamily.Ooxml => IsZipFamily(buffer, read),
            DocumentFamily.Text => IsPlausibleText(buffer, read),
            _ => false
        };

        if (!familyOk)
        {
            var reason = exeSignature != null
                ? $"content does not match declared type; matched executable signature {exeSignature}"
                : "content does not match declared type";
            throw RejectDocument(file, ext, "The file content does not match its declared type.", reason);
        }

        // Sanitise the untrusted filename and force the VALIDATED extension (a file validated as PDF is
        // stored as .pdf regardless of what the user typed).
        var safeName = SanitizeFileName(file.FileName, ext);
        return (MediaKind.Document, safeName);
    }

    // Log the rejection (user, declared MIME, extension, size, reason) and return the 400 to throw.
    private ValidationException RejectDocument(MediaUploadInput file, string ext, string clientMessage, string reason)
    {
        logger.LogWarning(
            "Document upload rejected | User: {User} | DeclaredMime: {Mime} | Extension: {Ext} | Size: {Size} | Reason: {Reason}",
            currentUser.UserId, file.ContentType, ext, file.Length, reason);
        return new ValidationException(clientMessage);
    }

    private static bool StartsWith(byte[] buffer, int len, params byte[] sig)
    {
        if (len < sig.Length) return false;
        for (var i = 0; i < sig.Length; i++)
            if (buffer[i] != sig[i]) return false;
        return true;
    }

    // A zip local-file header (PK\x03\x04), an empty archive (PK\x05\x06) or a spanned archive
    // (PK\x07\x08) are all the ZIP FAMILY. An OOXML doc is really a zip, so this confirms the family and
    // nothing more — it can never prove "this is specifically a Word document". Empty/spanned variants are
    // accepted as zip-family because the guarantee is deliberately family-level; we do not open the archive.
    private static bool IsZipFamily(byte[] buffer, int len) =>
        StartsWith(buffer, len, 0x50, 0x4B, 0x03, 0x04) ||
        StartsWith(buffer, len, 0x50, 0x4B, 0x05, 0x06) ||
        StartsWith(buffer, len, 0x50, 0x4B, 0x07, 0x08);

    // txt/csv have NO signature — there is nothing to match — so this is a bounded content HEURISTIC, NOT
    // a guarantee: a crafted file can pass it. It is acceptable here only because a .txt/.csv is never
    // executed, only stored and served. Inspects at most the first 8 KB (the caller's buffer). Rejects a
    // null byte (the clearest binary marker), a high proportion of non-printable control characters, and
    // anything that does not decode as UTF-8 (ASCII is a subset).
    private static bool IsPlausibleText(byte[] buffer, int len)
    {
        if (len == 0) return false;
        var nonPrintable = 0;
        for (var i = 0; i < len; i++)
        {
            var b = buffer[i];
            if (b == 0x00) return false;                                  // null byte → binary
            if (b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D) nonPrintable++;   // control (not tab/LF/CR)
        }
        if ((double)nonPrintable / len > 0.30) return false;             // mostly control chars → binary
        // Decode as UTF-8. Tolerate a multibyte char truncated by the 8 KB cap by retrying 3 bytes shorter.
        return DecodesAsUtf8(buffer, len) || DecodesAsUtf8(buffer, Math.Max(0, len - 3));
    }

    private static bool DecodesAsUtf8(byte[] buffer, int len)
    {
        try { _ = new UTF8Encoding(false, throwOnInvalidBytes: true).GetString(buffer, 0, len); return true; }
        catch (DecoderFallbackException) { return false; }
    }

    // Detect a known-executable leading signature — used ONLY to enrich the rejection log (attack signal),
    // never as the reason for rejection (that always comes from failing the allowlist/family check).
    private static string? DetectExecutableSignature(byte[] buffer, int len)
    {
        if (StartsWith(buffer, len, 0x4D, 0x5A)) return "MZ (Windows PE)";
        if (StartsWith(buffer, len, 0x7F, 0x45, 0x4C, 0x46)) return "ELF";
        if (StartsWith(buffer, len, 0x64, 0x65, 0x78, 0x0A)) return "dex (APK)";
        if (StartsWith(buffer, len, 0x23, 0x21)) return "#! (shebang)";
        return null;
    }

    // Sanitise an untrusted filename (see ADR 0004 §10). A filename carries real attacks:
    //   • Path traversal — keep only the base name, so ../../etc/passwd.pdf becomes passwd.pdf.
    //   • Null bytes / control characters — stripped.
    //   • Bidirectional-override characters (U+202A–202E, U+2066–2069, U+200E/200F) — stripped. These are
    //     a genuine spoof: report‮fdp.exe renders to the eye as reportexe.pdf. Skillora has real RTL
    //     users, so we STRIP the control characters while preserving legitimate Arabic/Urdu letters.
    //   • Length — truncated to 255 while preserving the extension.
    //   • Empty after sanitising — a generated stem is used.
    // The stored extension is ALWAYS the validated one, never whatever the user typed.
    private static string SanitizeFileName(string? original, string validatedExt)
    {
        var name = original ?? string.Empty;

        // Strip any path component (handles / and \ and traversal) — keep only the base name.
        var lastSep = name.LastIndexOfAny(new[] { '/', '\\' });
        if (lastSep >= 0) name = name[(lastSep + 1)..];

        var sb = new StringBuilder(name.Length);
        foreach (var ch in name)
        {
            if (ch < 0x20 || ch == 0x7F) continue;               // C0 controls + DEL (includes null)
            if (ch is '‎' or '‏') continue;            // LRM / RLM
            if (ch is >= '‪' and <= '‮') continue;     // LRE RLE PDF LRO RLO (incl. RTL override)
            if (ch is >= '⁦' and <= '⁩') continue;     // LRI RLI FSI PDI
            sb.Append(ch);
        }
        name = sb.ToString().Trim();

        // Drop the original extension — the stored extension MUST be the validated type. Everything
        // before the LAST dot is the stem (".pdf" → "" ; "report.pdf" → "report" ; "my.report.pdf" →
        // "my.report"); stray leading/trailing dots are trimmed so ".pdf" doesn't become ".pdf.pdf".
        var dot = name.LastIndexOf('.');
        var stem = (dot >= 0 ? name[..dot] : name).Trim().Trim('.');

        if (string.IsNullOrWhiteSpace(stem)) stem = "document";   // empty after sanitising → generated stem

        var maxStem = 255 - validatedExt.Length;                  // truncate preserving the extension
        if (stem.Length > maxStem) stem = stem[..maxStem];

        return stem + validatedExt;
    }

    // Read up to buffer.Length bytes, tolerating partial reads (a single ReadAsync may return fewer).
    private static async Task<int> ReadUpToAsync(Stream stream, byte[] buffer, CancellationToken ct)
    {
        var total = 0;
        while (total < buffer.Length)
        {
            var n = await stream.ReadAsync(buffer.AsMemory(total, buffer.Length - total), ct);
            if (n == 0) break;
            total += n;
        }
        return total;
    }

    // Leading-signature check per declared type. Only the first bytes are inspected.
    private static bool MagicBytesMatch(string contentType, byte[] h, int len)
    {
        bool Sig(params byte[] sig)
        {
            if (len < sig.Length) return false;
            for (var i = 0; i < sig.Length; i++)
                if (h[i] != sig[i]) return false;
            return true;
        }

        return contentType.ToLowerInvariant() switch
        {
            "image/jpeg"      => Sig(0xFF, 0xD8, 0xFF),
            "image/png"       => Sig(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A),
            "image/gif"       => Sig(0x47, 0x49, 0x46, 0x38),                                   // "GIF8" (87a/89a)
            "image/webp"      => len >= 12 && Sig(0x52, 0x49, 0x46, 0x46)                       // "RIFF"
                                 && h[8] == 0x57 && h[9] == 0x45 && h[10] == 0x42 && h[11] == 0x50, // "WEBP"
            "video/mp4"       => len >= 8 && h[4] == 0x66 && h[5] == 0x74 && h[6] == 0x79 && h[7] == 0x70, // ....ftyp
            "video/quicktime" => len >= 8 &&
                                 ((h[4] == 0x66 && h[5] == 0x74 && h[6] == 0x79 && h[7] == 0x70) ||       // ftyp (qt brand)
                                  (h[4] == 0x6D && h[5] == 0x6F && h[6] == 0x6F && h[7] == 0x76)),         // moov
            "video/webm"      => Sig(0x1A, 0x45, 0xDF, 0xA3),                                   // EBML / Matroska

            // ── Voice (M-M6) ─────────────────────────────────────────────────────────────────────────
            // audio/mp4 (m4a) carries the SAME ftyp box at offset 4 as an mp4 VIDEO — the two are
            // distinguished ONLY by the declared MIME (this switch is keyed on it), never by the shared
            // signature, so an mp4 video is never routed to the audio path or vice versa.
            "audio/mp4"       => len >= 8 && h[4] == 0x66 && h[5] == 0x74 && h[6] == 0x79 && h[7] == 0x70, // ....ftyp
            // AAC is either an ADTS stream (syncword 0xFFFx) or an ftyp-boxed .m4a — accept both.
            "audio/aac"       => (len >= 2 && h[0] == 0xFF && (h[1] & 0xF6) == 0xF0)                        // ADTS sync
                                 || (len >= 8 && h[4] == 0x66 && h[5] == 0x74 && h[6] == 0x79 && h[7] == 0x70),
            "audio/ogg"       => Sig(0x4F, 0x67, 0x67, 0x53),                                   // "OggS" (Ogg/Opus)
            "audio/webm"      => Sig(0x1A, 0x45, 0xDF, 0xA3),                                   // EBML (WebM/Opus)
            _                 => false
        };
    }

    // Upload to Cloudinary and build the payload. For video, the duration is only known from the upload
    // result (no ffmpeg) — if it exceeds the limit, the just-uploaded asset is deleted (it is a fresh,
    // unreferenced public id) and the send is rejected 400, so no orphan and no over-length video stored.
    private async Task<MediaMessagePayload> UploadMediaAsync(
        MediaKind kind, MediaUploadInput file, string? waveform, string? documentFileName, CancellationToken ct)
    {
        var result = kind switch
        {
            MediaKind.Image    => await mediaStorage.UploadImageAsync(file.Content, file.FileName, MediaFolder, ct),
            MediaKind.Video    => await mediaStorage.UploadVideoAsync(file.Content, file.FileName, MediaFolder, ct),
            MediaKind.Audio    => await mediaStorage.UploadAudioAsync(file.Content, file.FileName, MediaFolder, ct),
            _                  => await mediaStorage.UploadDocumentAsync(file.Content, file.FileName, MediaFolder, ct)
        };

        if (kind == MediaKind.Video && result.DurationMs is int videoMs && videoMs > MaxVideoDurationMs)
        {
            await mediaStorage.DeleteAsync(result.PublicId, MediaKind.Video, ct);
            throw new ValidationException(
                $"Video is too long — the maximum length is {MaxVideoDurationSeconds} seconds.");
        }

        // Voice duration is only known AFTER upload (no ffmpeg) — same limitation as video. Over the
        // limit → delete the just-uploaded, unreferenced asset and reject 400, so no orphan is stored.
        if (kind == MediaKind.Audio && result.DurationMs is int audioMs && audioMs > MaxAudioDurationMs)
        {
            await mediaStorage.DeleteAsync(result.PublicId, MediaKind.Audio, ct);
            throw new ValidationException(
                $"Voice note is too long — the maximum length is {MaxAudioDurationSeconds} seconds.");
        }

        // Voice carries the client-computed waveform and NO thumbnail/dimensions; a document carries a
        // filename and NO thumbnail/dimensions/duration/waveform; image and video carry thumbnail +
        // dimensions and never a waveform or filename.
        return new MediaMessagePayload
        {
            Type = kind switch
            {
                MediaKind.Image => MessageType.Image,
                MediaKind.Video => MessageType.Video,
                MediaKind.Audio => MessageType.Voice,
                _               => MessageType.File
            },
            MediaUrl = result.SecureUrl,
            MediaThumbnailUrl = kind is MediaKind.Audio or MediaKind.Document ? null : result.ThumbnailUrl,
            MediaWidth = kind is MediaKind.Audio or MediaKind.Document ? null : result.Width,
            MediaHeight = kind is MediaKind.Audio or MediaKind.Document ? null : result.Height,
            MediaDurationMs = result.DurationMs,   // null for a document
            MediaSizeBytes = result.Bytes,
            MediaMimeType = file.ContentType,
            MediaPublicId = result.PublicId,
            MediaWaveform = kind == MediaKind.Audio ? waveform : null,
            MediaFileName = kind == MediaKind.Document ? documentFileName : null
        };
    }

    // Validate the waveform SHAPE: comma-separated integers, each 0–100, at most 64 samples. Null/blank
    // is valid (the client renders a flat bar). A malformed value is a 400 — we never store garbage. The
    // normalized (re-joined, whitespace-trimmed) string is returned so the stored column is clean.
    private static string? ValidateWaveform(string? waveform)
    {
        if (string.IsNullOrWhiteSpace(waveform)) return null;

        var parts = waveform.Split(',');
        if (parts.Length > MaxWaveformSamples)
            throw new ValidationException($"Waveform has too many samples — the maximum is {MaxWaveformSamples}.");

        var samples = new int[parts.Length];
        for (var i = 0; i < parts.Length; i++)
        {
            if (!int.TryParse(parts[i].Trim(), out var v) || v < 0 || v > 100)
                throw new ValidationException("Waveform must be comma-separated integers between 0 and 100.");
            samples[i] = v;
        }
        return string.Join(",", samples);
    }

    // The resolved media for a message being created — from a fresh upload (send) or copied from a
    // source message (forward). Kept internal to the single write path so media can only enter through
    // SendCoreAsync, never a parallel path.
    private sealed class MediaMessagePayload
    {
        public required MessageType Type { get; init; }
        public required string MediaUrl { get; init; }
        // Nullable since M-M6: a voice note has no thumbnail and no dimensions (image/video always do).
        public string? MediaThumbnailUrl { get; init; }
        public int? MediaWidth { get; init; }
        public int? MediaHeight { get; init; }
        public int? MediaDurationMs { get; init; }
        public required long MediaSizeBytes { get; init; }
        public required string MediaMimeType { get; init; }
        public required string MediaPublicId { get; init; }
        public string? MediaWaveform { get; init; }   // voice only
        public string? MediaFileName { get; init; }    // document only (already sanitised)

        // Build from an existing source message (forward) — reuses the same asset, no re-upload.
        public static MediaMessagePayload FromMessage(Message m) => new()
        {
            Type = m.Type,
            MediaUrl = m.MediaUrl ?? string.Empty,
            MediaThumbnailUrl = m.MediaThumbnailUrl,
            MediaWidth = m.MediaWidth,
            MediaHeight = m.MediaHeight,
            MediaDurationMs = m.MediaDurationMs,
            MediaSizeBytes = m.MediaSizeBytes ?? 0,
            MediaMimeType = m.MediaMimeType ?? string.Empty,
            MediaPublicId = m.MediaPublicId ?? string.Empty,
            MediaWaveform = m.MediaWaveform,
            MediaFileName = m.MediaFileName   // forward preserves the document's filename, no re-upload
        };
    }
}
