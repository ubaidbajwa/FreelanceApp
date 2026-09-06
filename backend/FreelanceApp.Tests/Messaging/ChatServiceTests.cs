using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Messaging.DTOs;
using FreelanceApp.Application.Features.Messaging.Services;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging.Abstractions;

namespace FreelanceApp.Tests.Messaging;

public class ChatServiceTests
{
    private static readonly Guid Me = Guid.NewGuid();
    private static readonly Guid Other = Guid.NewGuid();
    private static readonly Guid Third = Guid.NewGuid();

    private static (ChatService sut, FakeConversationRepository convs, FakeUserRepository users, RecordingChatNotifier notifier)
        Build(Guid? caller = null)
    {
        var (sut, convs, users, _, notifier) = BuildAll(caller);
        return (sut, convs, users, notifier);
    }

    // Same as Build but also surfaces the media fake — used by the M-M4 media tests.
    private static (ChatService sut, FakeConversationRepository convs, FakeUserRepository users, FakeMediaStorageService media, RecordingChatNotifier notifier)
        BuildAll(Guid? caller = null)
    {
        var convs = new FakeConversationRepository();
        var users = new FakeUserRepository();
        var notifier = new RecordingChatNotifier();
        var media = new FakeMediaStorageService();
        var current = new FakeCurrentUser { UserId = caller ?? Me };
        var sut = new ChatService(convs, users, notifier, current, media, NullLogger<ChatService>.Instance);
        return (sut, convs, users, media, notifier);
    }

    private static Conversation Conv(Guid initiator, Guid other, ConversationStatus status)
    {
        var c = new Conversation { Id = Guid.NewGuid(), InitiatorId = initiator, Status = status, CreatedAt = DateTime.UtcNow };
        c.Participants.Add(new ConversationParticipant { ConversationId = c.Id, UserId = initiator, JoinedAt = DateTime.UtcNow });
        c.Participants.Add(new ConversationParticipant { ConversationId = c.Id, UserId = other, JoinedAt = DateTime.UtcNow });
        return c;
    }

    // ===== START / GET =====

    [Fact]
    public async Task Start_SelfRequest_Throws400()
    {
        var (sut, _, users, _) = Build();
        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.StartOrGetConversationAsync(Me));
        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task Start_RecipientMissing_Throws404()
    {
        var (sut, _, _, _) = Build();   // no users seeded
        var ex = await Assert.ThrowsAsync<NotFoundException>(() => sut.StartOrGetConversationAsync(Other));
        Assert.Equal(404, ex.StatusCode);
    }

    [Fact]
    public async Task Start_Connected_CreatesAcceptedConversation_NoRequestNotification()
    {
        var (sut, convs, users, notifier) = Build();
        users.Add(Other);
        convs.AcceptedConnections.Add((Me, Other));

        var summary = await sut.StartOrGetConversationAsync(Other);

        var conv = Assert.Single(convs.Conversations);
        Assert.Equal(ConversationStatus.Accepted, conv.Status);
        Assert.Equal(Me, conv.InitiatorId);
        Assert.Equal(2, conv.Participants.Count);
        Assert.False(summary.IsRequest);
        Assert.Empty(notifier.RequestReceived);
    }

    [Fact]
    public async Task Start_NotConnected_CreatesPendingRequest_DoesNotNotifyOnStart()
    {
        var (sut, convs, users, notifier) = Build();
        users.Add(Other);

        var summary = await sut.StartOrGetConversationAsync(Other);

        var conv = Assert.Single(convs.Conversations);
        Assert.Equal(ConversationStatus.Pending, conv.Status);
        Assert.Equal(Me, conv.InitiatorId);
        Assert.Equal(2, conv.Participants.Count);
        Assert.Equal(conv.Id, summary.Id);

        // No message exists yet — the request push must NOT fire on StartOrGet.
        Assert.Empty(notifier.RequestReceived);
    }

    [Fact]
    public async Task Start_ExistingConversation_ReturnsIt_NoDuplicate()
    {
        var (sut, convs, users, _) = Build();
        users.Add(Other);
        var existing = Conv(Other, Me, ConversationStatus.Accepted);
        convs.Conversations.Add(existing);

        var summary = await sut.StartOrGetConversationAsync(Other);

        Assert.Single(convs.Conversations);        // no new row
        Assert.Equal(existing.Id, summary.Id);
    }

    [Fact]
    public async Task Start_SecondCall_SameDirection_ReturnsSameConversation_NoDuplicate()
    {
        var (sut, convs, users, _) = Build();
        users.Add(Other);

        var first = await sut.StartOrGetConversationAsync(Other);
        var second = await sut.StartOrGetConversationAsync(Other);

        Assert.Equal(first.Id, second.Id);
        Assert.Single(convs.Conversations);
    }

    [Fact]
    public async Task Start_SecondCall_OppositeDirection_ReturnsSameConversation()
    {
        // Shared repo, two callers: Me starts with Other, then Other starts with Me.
        var convs = new FakeConversationRepository();
        var users = new FakeUserRepository();
        users.Add(Me);
        users.Add(Other);
        var notifier = new RecordingChatNotifier();

        var meService = new ChatService(convs, users, notifier,
            new FakeCurrentUser { UserId = Me }, new FakeMediaStorageService(), NullLogger<ChatService>.Instance);
        var first = await meService.StartOrGetConversationAsync(Other);

        var otherService = new ChatService(convs, users, notifier,
            new FakeCurrentUser { UserId = Other }, new FakeMediaStorageService(), NullLogger<ChatService>.Instance);
        var second = await otherService.StartOrGetConversationAsync(Me);

        Assert.Equal(first.Id, second.Id);   // get-or-create is direction-agnostic
        Assert.Single(convs.Conversations);
    }

    // ===== GET SINGLE (Fix 2) =====

    [Fact]
    public async Task GetConversation_ConversationMissing_Throws404()
    {
        var (sut, _, _, _) = Build();
        var ex = await Assert.ThrowsAsync<NotFoundException>(() => sut.GetConversationAsync(Guid.NewGuid()));
        Assert.Equal(404, ex.StatusCode);
    }

    [Fact]
    public async Task GetConversation_NotParticipant_Throws403()
    {
        var (sut, convs, _, _) = Build();   // caller = Me, not in conv
        var conv = Conv(Other, Third, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.GetConversationAsync(conv.Id));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task GetConversation_IsRequest_IsCallerRelative_BothDirectionsOnSamePending()
    {
        // One pending conversation, Me initiated. Two callers over the SAME repo.
        var convs = new FakeConversationRepository();
        var users = new FakeUserRepository();
        var notifier = new RecordingChatNotifier();
        var conv = Conv(Me, Other, ConversationStatus.Pending);
        convs.Conversations.Add(conv);

        var meSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Me }, new FakeMediaStorageService(), NullLogger<ChatService>.Instance);
        var otherSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Other }, new FakeMediaStorageService(), NullLogger<ChatService>.Instance);

        var mine = await meSvc.GetConversationAsync(conv.Id);
        Assert.Equal(conv.Id, mine.Id);
        Assert.False(mine.IsRequest);   // I'm the initiator — my own conversation, not a request to me

        var theirs = await otherSvc.GetConversationAsync(conv.Id);
        Assert.Equal(conv.Id, theirs.Id);
        Assert.True(theirs.IsRequest);   // to the recipient it's an incoming request
    }

    [Fact]
    public async Task GetConversation_MessageLessConversation_IsReturned_NotExcludedLikeLists()
    {
        var (sut, convs, _, _) = Build();
        // Freshly created, never messaged → LastMessageAt null. Lists exclude it; single-get must not.
        var conv = Conv(Me, Other, ConversationStatus.Pending);
        convs.Conversations.Add(conv);

        var summary = await sut.GetConversationAsync(conv.Id);

        Assert.Equal(conv.Id, summary.Id);
        Assert.Null(summary.LastMessageAt);
        // Contrast: the list query drops this exact thread.
        Assert.Empty((await sut.GetConversationsAsync(1, 20)).Items);
    }

    [Fact]
    public async Task GetConversation_UnreadCount_RespectsCallerLastReadWatermark()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var t0 = DateTime.UtcNow.AddMinutes(-5);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "one", CreatedAt = t0 });
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "two", CreatedAt = t0.AddMinutes(1) });
        conv.LastMessageAt = t0.AddMinutes(1);

        Assert.Equal(2, (await sut.GetConversationAsync(conv.Id)).UnreadCount);   // nothing read yet

        conv.Participants.Single(p => p.UserId == Me).LastReadAt = t0;   // read up to the first
        Assert.Equal(1, (await sut.GetConversationAsync(conv.Id)).UnreadCount);
    }

    // ===== SEND =====

    [Fact]
    public async Task Send_ConversationMissing_Throws404()
    {
        var (sut, _, _, _) = Build();
        var ex = await Assert.ThrowsAsync<NotFoundException>(
            () => sut.SendMessageAsync(Guid.NewGuid(), new SendMessageRequestDto { Body = "hi" }));
        Assert.Equal(404, ex.StatusCode);
    }

    [Fact]
    public async Task Send_NotParticipant_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Other, Third, ConversationStatus.Accepted);   // Me not in it
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "hi" }));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task Send_Declined_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Declined);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "hi" }));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task Send_PendingInitiator_SecondMessage_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Pending);
        convs.Conversations.Add(conv);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "first", CreatedAt = DateTime.UtcNow });

        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "second" }));
        Assert.Equal(403, ex.StatusCode);
        Assert.Contains("already sent", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Send_PendingInitiator_FirstMessage_Allowed_StaysPending()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Pending);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "hello" });

        Assert.Equal("hello", msg.Body);
        Assert.Equal(ConversationStatus.Pending, conv.Status);   // initiator's message does NOT accept
        Assert.NotNull(conv.LastMessageAt);
        Assert.Single(convs.Messages);
        var pushed = Assert.Single(notifier.MessageReceived);
        Assert.Contains(Me, pushed.userIds);
        Assert.Contains(Other, pushed.userIds);
    }

    [Fact]
    public async Task Send_InitiatorFirstMessage_IntoPending_NotifiesRecipientRequest_OnceWithPreview()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Pending);   // Me initiated
        convs.Conversations.Add(conv);

        await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "hi there" });

        var req = Assert.Single(notifier.RequestReceived);        // fired exactly once
        Assert.Equal(Other, req.userId);                          // recipient only, not the initiator
        Assert.True(req.conversation.IsRequest);                  // from recipient's perspective
        Assert.Equal("hi there", req.conversation.LastMessagePreview);   // populated — loaded after save
    }

    [Fact]
    public async Task Send_InitiatorSecondMessage_DoesNotFireRequestNotificationAgain()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Pending);
        convs.Conversations.Add(conv);

        await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "first" });
        Assert.Single(notifier.RequestReceived);

        // Second send is rejected by the 1-message rule — and must not push another request.
        await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "second" }));

        Assert.Single(notifier.RequestReceived);   // still exactly one
    }

    [Fact]
    public async Task Send_PendingRecipientReply_ImplicitlyAccepts()
    {
        var (sut, convs, _, _) = Build();   // caller = Me
        var conv = Conv(Other, Me, ConversationStatus.Pending);   // Other initiated, Me is recipient
        convs.Conversations.Add(conv);

        var msg = await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "sure!" });

        Assert.Equal(ConversationStatus.Accepted, conv.Status);
        Assert.NotNull(conv.RespondedAt);
        Assert.Equal("sure!", Assert.Single(convs.Messages).Body);
    }

    [Fact]
    public async Task Send_RecipientReplyToPending_FiresAcceptedToInitiator_AndMessageToAll()
    {
        var (sut, convs, _, notifier) = Build();   // caller = Me (recipient)
        var conv = Conv(Other, Me, ConversationStatus.Pending);   // Other initiated, Me is recipient
        convs.Conversations.Add(conv);

        await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "sure!" });

        // Initiator is told the thread flipped to Accepted (so its composer unlocks).
        var accepted = Assert.Single(notifier.Accepted);
        Assert.Equal(Other, accepted.userId);
        Assert.Equal(conv.Id, accepted.conversationId);

        // The reply itself still fans out to all participants.
        var pushed = Assert.Single(notifier.MessageReceived);
        Assert.Contains(Me, pushed.userIds);
        Assert.Contains(Other, pushed.userIds);
    }

    [Fact]
    public async Task Send_ToAcceptedConversation_FiresMessageOnly_NoAcceptedEvent()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);   // already accepted
        convs.Conversations.Add(conv);

        await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "hey" });

        Assert.Single(notifier.MessageReceived);
        Assert.Empty(notifier.Accepted);   // no state transition → no accepted event
    }

    [Fact]
    public async Task Send_Accepted_NormalSend_SetsLastMessageAt()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "yo" });

        Assert.NotNull(conv.LastMessageAt);
        Assert.Single(convs.Messages);
    }

    [Fact]
    public async Task Send_NotifierFailure_DoesNotFailRequest_MessageStillPersisted()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        notifier.Throw = true;

        var msg = await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "durable" });

        Assert.Equal("durable", msg.Body);
        Assert.Single(convs.Messages);   // persisted despite notifier throwing
    }

    [Fact]
    public async Task Send_NotifiesWithThePersistedMessage()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "hi" });

        Assert.Single(convs.Messages);                 // saved first
        var pushed = Assert.Single(notifier.MessageReceived);
        Assert.Equal(msg.Id, pushed.message.Id);       // then notified with that saved message
    }

    // ===== MEDIA (M-M4) =====

    private static readonly byte[] Jpeg = { 0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0 };
    private static readonly byte[] Png  = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0 };
    private static readonly byte[] Gif  = { 0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0, 0, 0, 0, 0 };
    private static readonly byte[] Webp = { 0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50 };
    private static readonly byte[] Mp4  = { 0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32 };
    private static readonly byte[] Webm = { 0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0, 0, 0, 0, 0 };
    private static readonly byte[] Mov  = { 0, 0, 0, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74, 0x20, 0x20 };

    private static MediaUploadInput Input(string contentType, byte[] bytes, long? length = null) =>
        new() { Content = new MemoryStream(bytes), FileName = "f", ContentType = contentType, Length = length ?? bytes.Length };

    private static SendMediaMessageRequestDto MediaReq(string? caption = null, Guid? replyTo = null) =>
        new() { Caption = caption, ReplyToMessageId = replyTo };

    [Theory]
    [InlineData("image/jpeg")]
    [InlineData("image/png")]
    [InlineData("image/webp")]
    [InlineData("image/gif")]
    public async Task SendMedia_AcceptedImageType_CreatesImageMessage_CaptionAsBody(string contentType)
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var bytes = contentType switch { "image/jpeg" => Jpeg, "image/png" => Png, "image/webp" => Webp, _ => Gif };

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(caption: "look here"), Input(contentType, bytes));

        Assert.Equal(MessageType.Image, msg.Type);
        Assert.Equal("look here", msg.Body);                 // caption stored as Body
        Assert.Equal(media.ImageResult.SecureUrl, msg.MediaUrl);
        Assert.Equal(media.ImageResult.ThumbnailUrl, msg.MediaThumbnailUrl);
        Assert.Equal(800, msg.MediaWidth);
        Assert.Equal(600, msg.MediaHeight);
        Assert.Equal(1, media.ImageUploads);
        Assert.Single(convs.Messages);
    }

    [Theory]
    [InlineData("video/mp4")]
    [InlineData("video/webm")]
    [InlineData("video/quicktime")]
    public async Task SendMedia_AcceptedVideoType_CreatesVideoMessage_EmptyCaptionAllowed(string contentType)
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var bytes = contentType switch { "video/mp4" => Mp4, "video/webm" => Webm, _ => Mov };

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(caption: null), Input(contentType, bytes));

        Assert.Equal(MessageType.Video, msg.Type);
        Assert.Equal(string.Empty, msg.Body);                // empty caption allowed for media
        Assert.Equal(5000, msg.MediaDurationMs);
        Assert.Equal(1, media.VideoUploads);
    }

    [Fact]
    public async Task SendMedia_OversizeImage_Rejected_NamingLimit_NoUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("image/jpeg", Jpeg, length: ChatService.MaxImageBytes + 1)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("10 MB", ex.Message);
        Assert.Equal(0, media.ImageUploads);                 // rejected before reaching Cloudinary
        Assert.Empty(convs.Messages);
    }

    [Fact]
    public async Task SendMedia_OversizeVideo_Rejected_NamingLimit_NoUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("video/mp4", Mp4, length: ChatService.MaxVideoBytes + 1)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("50 MB", ex.Message);
        Assert.Equal(0, media.VideoUploads);
    }

    [Fact]
    public async Task SendMedia_OverDurationVideo_Rejected_AndAssetDeleted_NoMessage()
    {
        var (sut, convs, _, media, _) = BuildAll();
        media.VideoDurationMs = ChatService.MaxVideoDurationMs + 1;   // 120.001 s
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("video/mp4", Mp4)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("120 seconds", ex.Message);
        Assert.Equal("skillora/chat/vid", Assert.Single(media.Deleted));   // uploaded, then cleaned up
        Assert.Empty(convs.Messages);                                       // no message persisted
    }

    [Fact]
    public async Task SendMedia_SpoofedExtension_RejectedOnMagicBytes_NoUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var notJpeg = new byte[] { 0x00, 0x01, 0x02, 0x03, 0, 0, 0, 0, 0, 0, 0, 0 };   // declared jpeg, isn't

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("image/jpeg", notJpeg)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Equal(0, media.ImageUploads);
        Assert.Empty(convs.Messages);
    }

    [Fact]
    public async Task SendMedia_UnsupportedType_Rejected()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("application/pdf", Jpeg)));

        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public void Validator_TextBodyRequired()
    {
        var text = new FreelanceApp.Application.Features.Messaging.Validators.SendMessageRequestValidator()
            .Validate(new SendMessageRequestDto { Body = "" });
        Assert.False(text.IsValid);   // empty text body is invalid
    }

    [Fact]
    public async Task SendMedia_NullCaption_Accepted()
    {
        // A media message may have no caption at all — this must succeed (the caption-optional rule,
        // enforced by ChatService now, not a validator that never ran on the multipart endpoint).
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(caption: null), Input("image/jpeg", Jpeg));

        Assert.Equal(string.Empty, msg.Body);
    }

    [Fact]
    public async Task SendMedia_CaptionTooLong_Rejected400_Not500()
    {
        // A 5000-char caption must be a clean 400 from ChatService — NOT a 500 when Body (varchar 4000)
        // overflows at SaveChanges. The old SendMediaMessageRequestValidator was dead code: the multipart
        // endpoint binds SendMediaMessageApiRequest, so auto-validation never ran the DTO validator.
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(caption: new string('x', 5000)), Input("image/jpeg", Jpeg)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Equal(0, media.ImageUploads);   // rejected before any upload
        Assert.Empty(convs.Messages);
    }

    [Fact]
    public async Task SendMedia_PendingInitiatorAtLimit_BlockedByRuleC_BeforeUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Pending);   // Me initiated
        convs.Conversations.Add(conv);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "first", CreatedAt = DateTime.UtcNow });

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("image/jpeg", Jpeg)));

        Assert.Equal(403, ex.StatusCode);
        Assert.Equal(0, media.ImageUploads);   // gate ran BEFORE upload — media send inherits rule (c), no orphan
    }

    [Fact]
    public async Task ForwardMedia_ReusesSamePublicId_WithoutReupload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var source = Conv(Me, Other, ConversationStatus.Accepted);
        var target = Conv(Me, Third, ConversationStatus.Accepted);
        convs.Conversations.Add(source);
        convs.Conversations.Add(target);
        var img = new Message
        {
            Id = Guid.NewGuid(), ConversationId = source.Id, SenderId = Me, Body = "cap",
            Type = MessageType.Image, CreatedAt = DateTime.UtcNow,
            MediaUrl = "https://x/img.jpg", MediaThumbnailUrl = "https://x/thumb.jpg",
            MediaWidth = 800, MediaHeight = 600, MediaMimeType = "image/jpeg",
            MediaSizeBytes = 1234, MediaPublicId = "skillora/chat/img"
        };
        convs.Messages.Add(img);

        var result = await sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = new List<Guid> { img.Id } });

        var fwd = Assert.Single(result);
        Assert.Equal(MessageType.Image, fwd.Type);
        Assert.Equal("https://x/img.jpg", fwd.MediaUrl);
        Assert.True(fwd.IsForwarded);
        Assert.Equal(0, media.ImageUploads);   // a forward is a reference, not a copy — no re-upload
        var persisted = convs.Messages.First(m => m.ConversationId == target.Id && m.Type == MessageType.Image);
        Assert.Equal("skillora/chat/img", persisted.MediaPublicId);   // SAME asset id
    }

    [Fact]
    public async Task EditMedia_Refused_400()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var img = new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "cap", Type = MessageType.Image, CreatedAt = DateTime.UtcNow };
        convs.Messages.Add(img);

        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.EditMessageAsync(conv.Id, img.Id, "new caption"));
        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task DeleteForEveryone_BlanksMediaUrlAndThumbnail_InProjection()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var img = new Message
        {
            Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "cap",
            Type = MessageType.Image, CreatedAt = DateTime.UtcNow,
            MediaUrl = "https://x/img.jpg", MediaThumbnailUrl = "https://x/thumb.jpg", MediaPublicId = "pid"
        };
        convs.Messages.Add(img);

        await sut.DeleteForEveryoneAsync(conv.Id, img.Id);
        var page = await sut.GetMessagesAsync(conv.Id, null, 30);

        var dto = Assert.Single(page.Items);
        Assert.True(dto.IsDeleted);
        Assert.Null(dto.MediaUrl);            // publicly-reachable URL must not leak for a tombstone
        Assert.Null(dto.MediaThumbnailUrl);
        Assert.Equal(string.Empty, dto.Body);
    }

    [Fact]
    public async Task List_LastMessageType_ReflectsUncaptionedPhoto()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        conv.LastMessageAt = DateTime.UtcNow;
        convs.Conversations.Add(conv);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "", Type = MessageType.Image, CreatedAt = DateTime.UtcNow });

        var list = await sut.GetConversationsAsync(1, 20);

        var row = Assert.Single(list.Items);
        Assert.Equal(MessageType.Image, row.LastMessageType);
        Assert.Equal("", row.LastMessagePreview);   // empty preview → client localises "Photo" from the type
    }

    // ===== VOICE (M-M6) =====

    private static readonly byte[] M4a = { 0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20 }; // ftyp M4A
    private static readonly byte[] Aac = { 0xFF, 0xF1, 0x50, 0x80, 0, 0, 0, 0, 0, 0, 0, 0 };                 // ADTS sync
    private static readonly byte[] Ogg = { 0x4F, 0x67, 0x67, 0x53, 0, 0, 0, 0, 0, 0, 0, 0 };                 // "OggS"
    // audio/webm shares the EBML signature with video/webm — reuse the Webm bytes.

    private static byte[] AudioBytes(string contentType) => contentType switch
    {
        "audio/mp4"  => M4a,
        "audio/aac"  => Aac,
        "audio/ogg"  => Ogg,
        _            => Webm
    };

    [Theory]
    [InlineData("audio/mp4")]
    [InlineData("audio/aac")]
    [InlineData("audio/ogg")]
    [InlineData("audio/webm")]
    public async Task SendVoice_AcceptedAudioType_CreatesVoiceMessage_NoThumbnailNoDimensions(string contentType)
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input(contentType, AudioBytes(contentType)));

        Assert.Equal(MessageType.Voice, msg.Type);
        Assert.Equal(string.Empty, msg.Body);              // a voice note has no caption
        Assert.Equal("https://res.cloudinary.com/x/video/upload/v1/skillora/chat/voice.m4a", msg.MediaUrl);
        Assert.Null(msg.MediaThumbnailUrl);                // no poster for audio
        Assert.Null(msg.MediaWidth);
        Assert.Null(msg.MediaHeight);
        Assert.Equal(8000, msg.MediaDurationMs);
        Assert.Equal(1, media.AudioUploads);
        Assert.Equal(0, media.ImageUploads + media.VideoUploads);   // routed to the audio path only
        Assert.Single(convs.Messages);
    }

    [Fact]
    public async Task SendVoice_OversizeAudio_Rejected_NamingLimit_NoUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("audio/mp4", M4a, length: ChatService.MaxAudioBytes + 1)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("10 MB", ex.Message);
        Assert.Equal(0, media.AudioUploads);
        Assert.Empty(convs.Messages);
    }

    [Fact]
    public async Task SendVoice_OverDurationAudio_Rejected_AndAssetDeleted_NoMessage()
    {
        var (sut, convs, _, media, _) = BuildAll();
        media.AudioDurationMs = ChatService.MaxAudioDurationMs + 1;   // 300.001 s
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("audio/mp4", M4a)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("300 seconds", ex.Message);
        Assert.Equal("skillora/chat/voice", Assert.Single(media.Deleted));   // uploaded, then cleaned up
        Assert.Empty(convs.Messages);
    }

    [Fact]
    public async Task SendVoice_VideoBytesDeclaredAsAudio_RejectedOnMagicBytes()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        // An mp4 VIDEO payload declared as audio/ogg — the OggS signature won't match, so it is refused.
        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("audio/ogg", Mp4)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Equal(0, media.AudioUploads);
    }

    [Fact]
    public async Task SendMedia_AudioBytesDeclaredAsVideo_RejectedOnMagicBytes()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        // An OGG AUDIO payload declared as video/mp4 — the ftyp signature won't match, so it is refused.
        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("video/mp4", Ogg)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Equal(0, media.VideoUploads);
    }

    [Fact]
    public async Task SendVoice_WithWaveform_StoredAndProjected()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMediaMessageAsync(conv.Id,
            new SendMediaMessageRequestDto { Waveform = "80,60,90,40" }, Input("audio/mp4", M4a));

        Assert.Equal("80,60,90,40", msg.MediaWaveform);
        var page = await sut.GetMessagesAsync(conv.Id, null, 30);
        Assert.Equal("80,60,90,40", Assert.Single(page.Items).MediaWaveform);   // projected on the page too
    }

    [Fact]
    public async Task SendVoice_NullWaveform_Accepted_StoresNull()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMediaMessageAsync(conv.Id,
            new SendMediaMessageRequestDto { Waveform = null }, Input("audio/mp4", M4a));

        Assert.Equal(MessageType.Voice, msg.Type);
        Assert.Null(msg.MediaWaveform);   // client will render a flat bar
    }

    [Theory]
    [InlineData("0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64")] // 65 samples
    [InlineData("80,101,60")]   // out of range (>100)
    [InlineData("80,-1,60")]    // out of range (<0)
    [InlineData("80,abc,60")]   // non-numeric
    public async Task SendVoice_MalformedWaveform_Rejected400(string waveform)
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, new SendMediaMessageRequestDto { Waveform = waveform }, Input("audio/mp4", M4a)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Empty(convs.Messages);   // rejected — nothing persisted
    }

    [Fact]
    public async Task SendVoice_PendingInitiatorAtLimit_BlockedByRuleC_BeforeUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Pending);   // Me initiated
        convs.Conversations.Add(conv);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "first", CreatedAt = DateTime.UtcNow });

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), Input("audio/mp4", M4a)));

        Assert.Equal(403, ex.StatusCode);
        Assert.Equal(0, media.AudioUploads);   // rule (c) ran BEFORE upload — no orphan asset
    }

    [Fact]
    public async Task ForwardVoice_ReusesSamePublicId_AndWaveform_WithoutReupload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var source = Conv(Me, Other, ConversationStatus.Accepted);
        var target = Conv(Me, Third, ConversationStatus.Accepted);
        convs.Conversations.Add(source);
        convs.Conversations.Add(target);
        var voice = new Message
        {
            Id = Guid.NewGuid(), ConversationId = source.Id, SenderId = Me, Body = string.Empty,
            Type = MessageType.Voice, CreatedAt = DateTime.UtcNow,
            MediaUrl = "https://x/voice.m4a", MediaMimeType = "audio/mp4", MediaDurationMs = 8000,
            MediaSizeBytes = 34567, MediaPublicId = "skillora/chat/voice", MediaWaveform = "10,20,30"
        };
        convs.Messages.Add(voice);

        var result = await sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = new List<Guid> { voice.Id } });

        var fwd = Assert.Single(result);
        Assert.Equal(MessageType.Voice, fwd.Type);
        Assert.Equal("https://x/voice.m4a", fwd.MediaUrl);
        Assert.Equal("10,20,30", fwd.MediaWaveform);
        Assert.True(fwd.IsForwarded);
        Assert.Equal(0, media.AudioUploads);   // a forward is a reference, not a copy
        var persisted = convs.Messages.First(m => m.ConversationId == target.Id && m.Type == MessageType.Voice);
        Assert.Equal("skillora/chat/voice", persisted.MediaPublicId);   // SAME asset id
    }

    [Fact]
    public async Task EditVoice_Refused_400()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = string.Empty, Type = MessageType.Voice, CreatedAt = DateTime.UtcNow };
        convs.Messages.Add(voice);

        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.EditMessageAsync(conv.Id, voice.Id, "caption"));
        Assert.Equal(400, ex.StatusCode);   // the M5 media edit-guard covers Voice, not just Image/Video
    }

    [Fact]
    public async Task DeleteForEveryoneVoice_BlanksMediaUrlAndWaveform_InProjection()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = new Message
        {
            Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = string.Empty,
            Type = MessageType.Voice, CreatedAt = DateTime.UtcNow,
            MediaUrl = "https://x/voice.m4a", MediaPublicId = "pid", MediaWaveform = "10,20,30"
        };
        convs.Messages.Add(voice);

        await sut.DeleteForEveryoneAsync(conv.Id, voice.Id);
        var page = await sut.GetMessagesAsync(conv.Id, null, 30);

        var dto = Assert.Single(page.Items);
        Assert.True(dto.IsDeleted);
        Assert.Null(dto.MediaUrl);
        Assert.Null(dto.MediaWaveform);   // a waveform left on a deleted voice note would be a small leak
    }

    [Fact]
    public async Task List_LastMessageType_ReflectsVoiceNote()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        conv.LastMessageAt = DateTime.UtcNow;
        convs.Conversations.Add(conv);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "", Type = MessageType.Voice, CreatedAt = DateTime.UtcNow });

        var list = await sut.GetConversationsAsync(1, 20);

        var row = Assert.Single(list.Items);
        Assert.Equal(MessageType.Voice, row.LastMessageType);   // client renders its own localised label
    }

    [Fact]
    public async Task ReplyToVoice_ReplyToCarriesVoiceType_EmptySnippet()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = string.Empty, Type = MessageType.Voice, CreatedAt = DateTime.UtcNow };
        convs.Messages.Add(voice);

        var dto = await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "replying to your voice", ReplyToMessageId = voice.Id });

        Assert.NotNull(dto.ReplyTo);
        Assert.Equal(MessageType.Voice, dto.ReplyTo!.Type);      // client renders its own "Voice message" label
        Assert.Equal(string.Empty, dto.ReplyTo.BodySnippet);     // no caption to quote
    }

    // ===== DOCUMENTS (M-M8) =====

    private static readonly byte[] Pdf  = { 0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0, 0, 0, 0 }; // %PDF-1.7
    private static readonly byte[] Zip  = { 0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0, 0, 0, 0, 0 };             // PK\x03\x04 (OOXML)
    private static readonly byte[] Ole2 = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0, 0, 0 }; // OLE2 compound
    private static readonly byte[] TextDoc = System.Text.Encoding.ASCII.GetBytes("name,role\nUbaid,dev\n");
    private static readonly byte[] Exe  = { 0x4D, 0x5A, 0x90, 0x00, 0, 0, 0, 0, 0, 0, 0, 0 };             // MZ (Windows PE)

    private const string DocxMime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    private const string XlsxMime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    private const string PptxMime = "application/vnd.openxmlformats-officedocument.presentationml.presentation";

    private static MediaUploadInput DocInput(string fileName, string contentType, byte[] bytes, long? length = null) =>
        new() { Content = new MemoryStream(bytes), FileName = fileName, ContentType = contentType, Length = length ?? bytes.Length };

    public static IEnumerable<object[]> AllowedDocs() => new[]
    {
        new object[] { "contract.pdf", "application/pdf", Pdf },
        new object[] { "report.docx",  DocxMime,          Zip },
        new object[] { "sheet.xlsx",   XlsxMime,          Zip },
        new object[] { "deck.pptx",    PptxMime,          Zip },
        new object[] { "old.doc",      "application/msword",           Ole2 },
        new object[] { "old.xls",      "application/vnd.ms-excel",     Ole2 },
        new object[] { "old.ppt",      "application/vnd.ms-powerpoint",Ole2 },
        new object[] { "notes.txt",    "text/plain",      TextDoc },
        new object[] { "data.csv",     "text/csv",        TextDoc },
    };

    [Theory]
    [MemberData(nameof(AllowedDocs))]
    public async Task SendDocument_AllowedType_CreatesFileMessage_FilenameStored(string fileName, string mime, byte[] bytes)
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(caption: "see attached"), DocInput(fileName, mime, bytes));

        Assert.Equal(MessageType.File, msg.Type);          // the reserved File = 2
        Assert.Equal("see attached", msg.Body);            // caption stored as Body
        Assert.Equal(fileName, msg.MediaFileName);         // clean name stored verbatim
        Assert.Equal("https://res.cloudinary.com/x/raw/upload/v1/skillora/chat/doc.pdf", msg.MediaUrl);
        Assert.Null(msg.MediaThumbnailUrl);                // no poster for a document
        Assert.Null(msg.MediaWidth);
        Assert.Null(msg.MediaHeight);
        Assert.Null(msg.MediaDurationMs);
        Assert.Equal(1, media.DocumentUploads);
        Assert.Equal(0, media.ImageUploads + media.VideoUploads + media.AudioUploads);   // document path only
        Assert.Single(convs.Messages);
    }

    [Fact]
    public async Task SendDocument_ExecutableExtension_RejectedOnExtension_NoUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput("malware.exe", "application/octet-stream", Exe)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("Unsupported file type", ex.Message);
        Assert.Equal(0, media.DocumentUploads);            // rejected at the extension layer, no upload
        Assert.Empty(convs.Messages);
    }

    [Fact]
    public async Task SendDocument_ExecutableRenamedToPdf_RejectedOnMagicBytes_NoUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        // An MZ payload declared as a PDF: passes extension + MIME, fails the %PDF- family check.
        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput("invoice.pdf", "application/pdf", Exe)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("content does not match", ex.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(0, media.DocumentUploads);
        Assert.Empty(convs.Messages);
    }

    [Fact]
    public async Task SendDocument_Zip_Rejected_NotOnAllowlist()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput("archive.zip", "application/zip", Zip)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Equal(0, media.DocumentUploads);            // .zip is deliberately excluded from the allowlist
    }

    [Fact]
    public async Task SendDocument_Oversize_Rejected_NamingLimit_NoUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput("big.pdf", "application/pdf", Pdf, length: ChatService.MaxDocumentBytes + 1)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("25 MB", ex.Message);
        Assert.Equal(0, media.DocumentUploads);            // size checked before reading the whole file
    }

    [Fact]
    public async Task SendDocument_ExtensionMimeMismatch_Rejected()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        // A .pdf declared text/plain — inconsistent regardless of the bytes.
        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput("contract.pdf", "text/plain", Pdf)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("inconsistent", ex.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(0, media.DocumentUploads);
    }

    [Fact]
    public async Task SendDocument_DocxWithOle2Bytes_RejectedOnFamilyMismatch()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        // A .docx (declared correctly) whose bytes are OLE2, not zip — family mismatch.
        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput("report.docx", DocxMime, Ole2)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Contains("content does not match", ex.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(0, media.DocumentUploads);
    }

    [Fact]
    public async Task SendDocument_TxtWithNullBytes_Rejected()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var nullish = new byte[] { 0x68, 0x69, 0x00, 0x68, 0x69 };   // "hi\0hi" — a null byte marks binary
        var ex = await Assert.ThrowsAsync<ValidationException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput("notes.txt", "text/plain", nullish)));

        Assert.Equal(400, ex.StatusCode);
        Assert.Equal(0, media.DocumentUploads);
    }

    [Fact]
    public async Task SendDocument_ValidTxt_Accepted()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput("notes.txt", "text/plain", TextDoc));

        Assert.Equal(MessageType.File, msg.Type);
        Assert.Equal("notes.txt", msg.MediaFileName);
        Assert.Equal(1, media.DocumentUploads);
    }

    [Theory]
    [InlineData("../../../etc/passwd.pdf", "passwd.pdf")]      // path traversal — keep only the base name
    [InlineData("..\\..\\secret.pdf", "secret.pdf")]           // windows-style path stripped
    public async Task SendDocument_FileName_PathStripped(string given, string expected)
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput(given, "application/pdf", Pdf));

        Assert.Equal(expected, msg.MediaFileName);
    }

    // Crafted attack names are built at RUNTIME with (char) casts so the source file stays plain ASCII
    // (an embedded null or RTL-override byte in source is fragile). Each still exercises real stripping.
    [Fact]
    public async Task SendDocument_FileName_NullAndControlCharsStripped()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var given = "re" + (char)0x00 + "po" + (char)0x1F + "rt.pdf";   // null + a C0 control char

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput(given, "application/pdf", Pdf));

        Assert.Equal("report.pdf", msg.MediaFileName);
    }

    [Fact]
    public async Task SendDocument_FileName_RtlOverrideStripped()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        // report<U+202E>fdp.pdf renders to the eye as reportexe.pdf — the override must be stripped.
        var given = "report" + (char)0x202E + "fdp.pdf";

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput(given, "application/pdf", Pdf));

        Assert.Equal("reportfdp.pdf", msg.MediaFileName);
    }

    [Fact]
    public async Task SendDocument_OverLengthFileName_TruncatedPreservingExtension()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput(new string('a', 300) + ".pdf", "application/pdf", Pdf));

        Assert.Equal(255, msg.MediaFileName!.Length);        // truncated to the 255 cap
        Assert.EndsWith(".pdf", msg.MediaFileName);          // extension preserved
    }

    [Fact]
    public async Task SendDocument_EmptyAfterSanitising_UsesGeneratedName()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        // Only bidi controls + extension → stem empty after stripping → generated "document".
        var given = ((char)0x202E).ToString() + (char)0x202D + ".pdf";

        var msg = await sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput(given, "application/pdf", Pdf));

        Assert.Equal("document.pdf", msg.MediaFileName);
    }

    [Fact]
    public async Task SendDocument_PendingInitiatorAtLimit_BlockedByRuleC_BeforeUpload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Pending);   // Me initiated
        convs.Conversations.Add(conv);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "first", CreatedAt = DateTime.UtcNow });

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() =>
            sut.SendMediaMessageAsync(conv.Id, MediaReq(), DocInput("x.pdf", "application/pdf", Pdf)));

        Assert.Equal(403, ex.StatusCode);
        Assert.Equal(0, media.DocumentUploads);              // rule (c) ran before upload — no orphan asset
    }

    [Fact]
    public async Task ForwardDocument_ReusesSamePublicIdAndFileName_WithoutReupload()
    {
        var (sut, convs, _, media, _) = BuildAll();
        var source = Conv(Me, Other, ConversationStatus.Accepted);
        var target = Conv(Me, Third, ConversationStatus.Accepted);
        convs.Conversations.Add(source);
        convs.Conversations.Add(target);
        var doc = new Message
        {
            Id = Guid.NewGuid(), ConversationId = source.Id, SenderId = Me, Body = "cap",
            Type = MessageType.File, CreatedAt = DateTime.UtcNow,
            MediaUrl = "https://x/doc.pdf", MediaMimeType = "application/pdf",
            MediaSizeBytes = 4096, MediaPublicId = "skillora/chat/doc", MediaFileName = "contract.pdf"
        };
        convs.Messages.Add(doc);

        var result = await sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = new List<Guid> { doc.Id } });

        var fwd = Assert.Single(result);
        Assert.Equal(MessageType.File, fwd.Type);
        Assert.Equal("https://x/doc.pdf", fwd.MediaUrl);
        Assert.Equal("contract.pdf", fwd.MediaFileName);     // filename shared, no re-upload
        Assert.True(fwd.IsForwarded);
        Assert.Equal(0, media.DocumentUploads);
        var persisted = convs.Messages.First(m => m.ConversationId == target.Id && m.Type == MessageType.File);
        Assert.Equal("skillora/chat/doc", persisted.MediaPublicId);   // SAME asset id
        Assert.Equal("contract.pdf", persisted.MediaFileName);
    }

    [Fact]
    public async Task EditDocument_Refused_400()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var doc = new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "cap", Type = MessageType.File, CreatedAt = DateTime.UtcNow };
        convs.Messages.Add(doc);

        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.EditMessageAsync(conv.Id, doc.Id, "new caption"));
        Assert.Equal(400, ex.StatusCode);                    // the media edit-guard now covers File too
    }

    [Fact]
    public async Task DeleteForEveryoneDocument_BlanksUrlAndFileName_InProjection()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var doc = new Message
        {
            Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "cap",
            Type = MessageType.File, CreatedAt = DateTime.UtcNow,
            MediaUrl = "https://x/doc.pdf", MediaPublicId = "pid", MediaFileName = "salary_negotiation_final.pdf"
        };
        convs.Messages.Add(doc);

        await sut.DeleteForEveryoneAsync(conv.Id, doc.Id);
        var page = await sut.GetMessagesAsync(conv.Id, null, 30);

        var dto = Assert.Single(page.Items);
        Assert.True(dto.IsDeleted);
        Assert.Null(dto.MediaUrl);
        Assert.Null(dto.MediaFileName);                      // a filename leaks meaning even when the file is gone
        Assert.Equal(string.Empty, dto.Body);
    }

    [Fact]
    public async Task ReplyToDocument_ReplyToCarriesFileName()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var doc = new Message
        {
            Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = string.Empty,
            Type = MessageType.File, CreatedAt = DateTime.UtcNow, MediaFileName = "contract.pdf", MediaUrl = "https://x/doc.pdf"
        };
        convs.Messages.Add(doc);

        var dto = await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "signed?", ReplyToMessageId = doc.Id });

        Assert.NotNull(dto.ReplyTo);
        Assert.Equal(MessageType.File, dto.ReplyTo!.Type);
        Assert.Equal("contract.pdf", dto.ReplyTo.FileName);  // reply quotes the filename, not a generic label
    }

    [Fact]
    public async Task List_LastMessageType_ReflectsDocument()
    {
        var (sut, convs, _, _, _) = BuildAll();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        conv.LastMessageAt = DateTime.UtcNow;
        convs.Conversations.Add(conv);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "", Type = MessageType.File, CreatedAt = DateTime.UtcNow, MediaFileName = "contract.pdf" });

        var list = await sut.GetConversationsAsync(1, 20);

        var row = Assert.Single(list.Items);
        Assert.Equal(MessageType.File, row.LastMessageType);   // client renders its own localised "Document" label
    }

    // ===== VOICE "PLAYED" RECEIPTS (M-M7) =====

    // Seed a voice note sent by `sender` in `conv`, returning it.
    private static Message SeedVoice(FakeConversationRepository convs, Conversation conv, Guid sender, bool deleted = false)
    {
        var v = new Message
        {
            Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = sender, Body = string.Empty,
            Type = MessageType.Voice, CreatedAt = DateTime.UtcNow.AddMinutes(-1),
            MediaUrl = "https://x/voice.m4a", MediaPublicId = "pid",
            DeletedAt = deleted ? DateTime.UtcNow : null
        };
        convs.Messages.Add(v);
        return v;
    }

    [Fact]
    public async Task MarkPlayed_CreatesRecord_AndNotifiesSenderOnly()
    {
        var (sut, convs, _, notifier) = Build();   // caller = Me (the recipient/player)
        var conv = Conv(Other, Me, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = SeedVoice(convs, conv, sender: Other);

        await sut.MarkPlayedAsync(conv.Id, voice.Id);

        var play = Assert.Single(convs.Plays);
        Assert.Equal(voice.Id, play.MessageId);
        Assert.Equal(Me, play.UserId);
        var evt = Assert.Single(notifier.Played);
        Assert.Equal(Other, evt.userId);          // sender only — never the player
        Assert.Equal(conv.Id, evt.conversationId);
        Assert.Equal(voice.Id, evt.messageId);
    }

    [Fact]
    public async Task MarkPlayed_SecondCall_Idempotent_NoSecondEvent()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Other, Me, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = SeedVoice(convs, conv, sender: Other);

        await sut.MarkPlayedAsync(conv.Id, voice.Id);
        await sut.MarkPlayedAsync(conv.Id, voice.Id);

        Assert.Single(convs.Plays);        // still exactly one record
        Assert.Single(notifier.Played);    // and exactly one event — the repeat pushed nothing
    }

    [Fact]
    public async Task MarkPlayed_NotParticipant_Throws403()
    {
        var (sut, convs, _, _) = Build();   // caller = Me, not in conv
        var conv = Conv(Other, Third, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = SeedVoice(convs, conv, sender: Other);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.MarkPlayedAsync(conv.Id, voice.Id));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task MarkPlayed_UnknownMessage_Throws404()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Other, Me, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<NotFoundException>(() => sut.MarkPlayedAsync(conv.Id, Guid.NewGuid()));
        Assert.Equal(404, ex.StatusCode);
    }

    [Fact]
    public async Task MarkPlayed_TextMessage_Throws400()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Other, Me, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var text = new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "hi", Type = MessageType.Text, CreatedAt = DateTime.UtcNow };
        convs.Messages.Add(text);

        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.MarkPlayedAsync(conv.Id, text.Id));
        Assert.Equal(400, ex.StatusCode);
        Assert.Empty(convs.Plays);
    }

    [Fact]
    public async Task MarkPlayed_OwnVoiceNote_Throws400()
    {
        var (sut, convs, _, _) = Build();   // caller = Me
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = SeedVoice(convs, conv, sender: Me);   // I sent it

        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.MarkPlayedAsync(conv.Id, voice.Id));
        Assert.Equal(400, ex.StatusCode);   // a sender cannot manufacture their own played receipt
        Assert.Empty(convs.Plays);
    }

    [Fact]
    public async Task MarkPlayed_TombstonedVoiceNote_Throws400()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Other, Me, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = SeedVoice(convs, conv, sender: Other, deleted: true);

        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.MarkPlayedAsync(conv.Id, voice.Id));
        Assert.Equal(400, ex.StatusCode);
        Assert.Empty(convs.Plays);
    }

    [Fact]
    public async Task MarkPlayed_NotifierFailure_DoesNotFailRequest_RecordPersisted()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Other, Me, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = SeedVoice(convs, conv, sender: Other);
        notifier.Throw = true;

        await sut.MarkPlayedAsync(conv.Id, voice.Id);   // must not throw

        Assert.Single(convs.Plays);   // persisted despite notifier throwing
    }

    [Fact]
    public async Task PlayedFlags_BothFalse_BeforeAnyPlay()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Other, Me, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        SeedVoice(convs, conv, sender: Other);

        var dto = Assert.Single((await sut.GetMessagesAsync(conv.Id, null, 30)).Items);
        Assert.False(dto.PlayedByMe);
        Assert.False(dto.PlayedByOther);
    }

    [Fact]
    public async Task PlayedFlags_AreCallerRelative_BothDirectionsOnSameMessage()
    {
        // One voice note sent by Me; Other (the recipient) plays it. Two callers over the SAME repo.
        var convs = new FakeConversationRepository();
        var users = new FakeUserRepository();
        var notifier = new RecordingChatNotifier();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = SeedVoice(convs, conv, sender: Me);

        var meSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Me }, new FakeMediaStorageService(), NullLogger<ChatService>.Instance);
        var otherSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Other }, new FakeMediaStorageService(), NullLogger<ChatService>.Instance);

        await otherSvc.MarkPlayedAsync(conv.Id, voice.Id);   // the recipient plays

        // Sender's view: I didn't play it, but the other participant did.
        var mine = Assert.Single((await meSvc.GetMessagesAsync(conv.Id, null, 30)).Items);
        Assert.False(mine.PlayedByMe);
        Assert.True(mine.PlayedByOther);

        // Player's view: I played it; from my side "other" is the sender, who did not.
        var theirs = Assert.Single((await otherSvc.GetMessagesAsync(conv.Id, null, 30)).Items);
        Assert.True(theirs.PlayedByMe);
        Assert.False(theirs.PlayedByOther);
    }

    [Fact]
    public async Task PlayedFlags_Blanked_ForTombstone()
    {
        var (sut, convs, _, _) = Build();   // caller = Me
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var voice = SeedVoice(convs, conv, sender: Me);
        convs.Plays.Add(new MessagePlay { MessageId = voice.Id, UserId = Other, PlayedAt = DateTime.UtcNow });

        // Before deletion: playedByOther is true from the sender's view.
        Assert.True(Assert.Single((await sut.GetMessagesAsync(conv.Id, null, 30)).Items).PlayedByOther);

        await sut.DeleteForEveryoneAsync(conv.Id, voice.Id);

        var dto = Assert.Single((await sut.GetMessagesAsync(conv.Id, null, 30)).Items);
        Assert.True(dto.IsDeleted);
        Assert.False(dto.PlayedByMe);      // both flags blanked for a tombstone, like the media fields
        Assert.False(dto.PlayedByOther);
    }

    // ===== ACCEPT / DECLINE =====

    [Fact]
    public async Task Accept_ByRecipient_SetsAccepted_NotifiesInitiator()
    {
        var (sut, convs, _, notifier) = Build();   // caller = Me (recipient)
        var conv = Conv(Other, Me, ConversationStatus.Pending);
        convs.Conversations.Add(conv);

        await sut.AcceptAsync(conv.Id);

        Assert.Equal(ConversationStatus.Accepted, conv.Status);
        Assert.NotNull(conv.RespondedAt);
        var notified = Assert.Single(notifier.Accepted);
        Assert.Equal(Other, notified.userId);   // initiator told
        Assert.Equal(conv.Id, notified.conversationId);
    }

    [Fact]
    public async Task Accept_ByInitiator_Throws403()
    {
        var (sut, convs, _, _) = Build();   // caller = Me (initiator)
        var conv = Conv(Me, Other, ConversationStatus.Pending);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.AcceptAsync(conv.Id));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task Accept_ByNonParticipant_Throws403()
    {
        var (sut, convs, _, _) = Build();   // caller = Me, not in conv
        var conv = Conv(Other, Third, ConversationStatus.Pending);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.AcceptAsync(conv.Id));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task Accept_NotPending_Throws409()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Other, Me, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ConflictException>(() => sut.AcceptAsync(conv.Id));
        Assert.Equal(409, ex.StatusCode);
    }

    [Fact]
    public async Task Decline_ByRecipient_SetsDeclined_NoNotification()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Other, Me, ConversationStatus.Pending);
        convs.Conversations.Add(conv);

        await sut.DeclineAsync(conv.Id);

        Assert.Equal(ConversationStatus.Declined, conv.Status);
        Assert.NotNull(conv.RespondedAt);
        Assert.Empty(notifier.Accepted);
    }

    // ===== MESSAGES (cursor) =====

    [Fact]
    public async Task GetMessages_NotParticipant_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Other, Third, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.GetMessagesAsync(conv.Id, null, 30));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task GetMessages_NewestFirst_CursorAndHasMore()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var t0 = DateTime.UtcNow.AddMinutes(-10);
        for (var i = 0; i < 5; i++)
            convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = $"m{i}", CreatedAt = t0.AddMinutes(i) });

        var first = await sut.GetMessagesAsync(conv.Id, null, 2);
        Assert.Equal(new[] { "m4", "m3" }, first.Items.Select(m => m.Body).ToArray());
        Assert.True(first.HasMore);
        Assert.Equal(first.Items[^1].CreatedAt, first.NextCursor);   // oldest returned

        var second = await sut.GetMessagesAsync(conv.Id, first.NextCursor, 2);
        Assert.Equal(new[] { "m2", "m1" }, second.Items.Select(m => m.Body).ToArray());
        Assert.True(second.HasMore);

        var third = await sut.GetMessagesAsync(conv.Id, second.NextCursor, 2);
        Assert.Equal(new[] { "m0" }, third.Items.Select(m => m.Body).ToArray());
        Assert.False(third.HasMore);   // nothing older
    }

    [Fact]
    public async Task GetMessages_LimitClampedTo50()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "x", CreatedAt = DateTime.UtcNow });

        // limit 1000 clamps to 50 — repo receives 51 (take+1 probe); with one message, HasMore false.
        var page = await sut.GetMessagesAsync(conv.Id, null, 1000);
        Assert.Single(page.Items);
        Assert.False(page.HasMore);
        Assert.Equal(50, convs.LastMessageLimitRequested - 1);   // probe was clamp(50) + 1
    }

    // ===== READ RECEIPT =====

    [Fact]
    public async Task MarkRead_SetsCallerLastReadAt()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        await sut.MarkReadAsync(conv.Id);

        var myPart = conv.Participants.Single(p => p.UserId == Me);
        Assert.NotNull(myPart.LastReadAt);
    }

    [Fact]
    public async Task MarkRead_NotParticipant_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Other, Third, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.MarkReadAsync(conv.Id));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task MarkRead_ZeroesUnreadCount()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var t0 = DateTime.UtcNow.AddMinutes(-5);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "unread", CreatedAt = t0 });
        conv.LastMessageAt = t0;

        Assert.Equal(1, (await sut.GetConversationsAsync(1, 20)).Items[0].UnreadCount);

        await sut.MarkReadAsync(conv.Id);   // LastReadAt = now, after the message

        Assert.Equal(0, (await sut.GetConversationsAsync(1, 20)).Items[0].UnreadCount);
    }

    [Fact]
    public async Task MarkRead_MovesForward_FiresConversationRead_ToOtherParticipantOnly()
    {
        var (sut, convs, _, notifier) = Build();   // caller = Me
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var t0 = DateTime.UtcNow.AddMinutes(-5);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "unread", CreatedAt = t0 });
        conv.LastMessageAt = t0;   // there IS new activity to read

        await sut.MarkReadAsync(conv.Id);

        var evt = Assert.Single(notifier.ConversationRead);
        Assert.Equal(Other, evt.userId);              // the reader (Me) is NOT told they read
        Assert.Equal(conv.Id, evt.conversationId);
        var myPart = conv.Participants.Single(p => p.UserId == Me);
        Assert.Equal(myPart.LastReadAt, evt.lastReadAt);   // payload carries the new watermark
    }

    [Fact]
    public async Task MarkRead_WatermarkDoesNotMoveForward_FiresNoConversationRead()
    {
        var (sut, convs, _, notifier) = Build();   // caller = Me
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var t0 = DateTime.UtcNow.AddMinutes(-5);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "already read", CreatedAt = t0 });
        conv.LastMessageAt = t0;
        // I've already read up to the last activity — a debounced re-mark reports nothing new.
        conv.Participants.Single(p => p.UserId == Me).LastReadAt = t0;

        await sut.MarkReadAsync(conv.Id);

        Assert.Empty(notifier.ConversationRead);   // no-op read → no noise event
    }

    [Fact]
    public async Task MarkRead_NotifierFailure_DoesNotFailRequest_WatermarkStillPersisted()
    {
        var (sut, convs, _, notifier) = Build();   // caller = Me
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var t0 = DateTime.UtcNow.AddMinutes(-5);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "unread", CreatedAt = t0 });
        conv.LastMessageAt = t0;
        notifier.Throw = true;

        await sut.MarkReadAsync(conv.Id);   // must not throw

        Assert.NotNull(conv.Participants.Single(p => p.UserId == Me).LastReadAt);   // persisted despite notifier down
    }

    // ===== LISTS (clamp + delegation) =====

    [Fact]
    public async Task GetConversations_ClampsPageSizeAndReturnsAcceptedOnly()
    {
        var (sut, convs, _, _) = Build();
        var accepted = Conv(Me, Other, ConversationStatus.Accepted);
        accepted.LastMessageAt = DateTime.UtcNow;   // has activity → listed
        convs.Conversations.Add(accepted);
        convs.Conversations.Add(Conv(Third, Me, ConversationStatus.Pending));   // a request, excluded

        var page = await sut.GetConversationsAsync(1, 1000);

        Assert.Equal(50, page.PageSize);   // clamped
        Assert.Single(page.Items);
        Assert.Equal(ConversationStatus.Accepted, page.Items[0].Status);
    }

    [Fact]
    public async Task GetRequests_ReturnsIncomingPendingOnly()
    {
        var (sut, convs, _, _) = Build();
        var incoming = Conv(Third, Me, ConversationStatus.Pending);   // incoming request
        incoming.LastMessageAt = DateTime.UtcNow;                     // has its request message → listed
        convs.Conversations.Add(incoming);
        convs.Conversations.Add(Conv(Me, Other, ConversationStatus.Pending));   // my own outgoing, excluded

        var page = await sut.GetRequestsAsync(1, 20);

        Assert.Single(page.Items);
        Assert.True(page.Items[0].IsRequest);
    }

    [Fact]
    public async Task GetConversations_UnreadCount_ExcludesCallersOwnMessages()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var t0 = DateTime.UtcNow.AddMinutes(-5);
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Me, Body = "mine", CreatedAt = t0 });
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "theirs1", CreatedAt = t0.AddMinutes(1) });
        convs.Messages.Add(new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "theirs2", CreatedAt = t0.AddMinutes(2) });
        conv.LastMessageAt = t0.AddMinutes(2);

        var page = await sut.GetConversationsAsync(1, 20);

        Assert.Equal(2, Assert.Single(page.Items).UnreadCount);   // caller's own "mine" not counted
    }

    // ===== MESSAGE ACTIONS (M1.2) =====

    private static Message Msg(Guid convId, Guid sender, string body, DateTime? at = null, DateTime? deletedAt = null)
        => new()
        {
            Id = Guid.NewGuid(), ConversationId = convId, SenderId = sender, Body = body,
            Type = MessageType.Text, CreatedAt = at ?? DateTime.UtcNow, DeletedAt = deletedAt
        };

    private static Message SysMsg(Guid convId, Guid actor, SystemEventType evtType, Guid targetId)
        => new()
        {
            Id = Guid.NewGuid(), ConversationId = convId, SenderId = actor, Body = string.Empty,
            Type = MessageType.System, SystemEventType = evtType, SystemTargetMessageId = targetId,
            CreatedAt = DateTime.UtcNow
        };

    // ----- Reactions -----

    [Fact]
    public async Task React_NotParticipant_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Other, Third, ConversationStatus.Accepted);   // Me not in it
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "hi"); convs.Messages.Add(m);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.ReactAsync(conv.Id, m.Id, "👍"));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task React_MessageNotInConversation_Throws404()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var ex = await Assert.ThrowsAsync<NotFoundException>(() => sut.ReactAsync(conv.Id, Guid.NewGuid(), "👍"));
        Assert.Equal(404, ex.StatusCode);
    }

    [Fact]
    public async Task React_AddsReaction_FiresReactionChanged_ReturnsCallerView()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "hi"); convs.Messages.Add(m);

        var view = await sut.ReactAsync(conv.Id, m.Id, "👍");

        var bucket = Assert.Single(view);
        Assert.Equal("👍", bucket.Emoji);
        Assert.Equal(1, bucket.Count);
        Assert.True(bucket.ReactedByMe);

        var evt = Assert.Single(notifier.ReactionChanged);
        Assert.Contains(Me, evt.userIds);
        Assert.Contains(Other, evt.userIds);
        Assert.Equal(m.Id, evt.messageId);
        Assert.False(Assert.Single(evt.reactions).ReactedByMe);   // event is caller-agnostic
    }

    [Fact]
    public async Task React_Again_ReplacesEmoji_NoSecondRow()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "hi"); convs.Messages.Add(m);

        await sut.ReactAsync(conv.Id, m.Id, "👍");
        var view = await sut.ReactAsync(conv.Id, m.Id, "❤️");

        Assert.Single(convs.Reactions);                 // replaced in place, not a second row
        var bucket = Assert.Single(view);
        Assert.Equal("❤️", bucket.Emoji);
        Assert.Equal(1, bucket.Count);
    }

    [Fact]
    public async Task React_SameEmojiAgain_TogglesItOff_ViaPut()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "hi"); convs.Messages.Add(m);

        await sut.ReactAsync(conv.Id, m.Id, "👍");        // set
        var view = await sut.ReactAsync(conv.Id, m.Id, "👍");  // same emoji again → clears (WhatsApp toggle)

        Assert.Empty(convs.Reactions);                    // reaction removed, not persisted unchanged
        Assert.Empty(view);                               // caller-view reflects the cleared state
        Assert.Equal(2, notifier.ReactionChanged.Count);  // set + clear both fan out
    }

    [Fact]
    public async Task Reaction_Toggle_RemoveClearsIt_Idempotent()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "hi"); convs.Messages.Add(m);

        await sut.ReactAsync(conv.Id, m.Id, "👍");
        await sut.RemoveReactionAsync(conv.Id, m.Id);
        Assert.Empty(convs.Reactions);

        // Removing again is a no-op (no throw).
        await sut.RemoveReactionAsync(conv.Id, m.Id);
        Assert.Empty(convs.Reactions);
        Assert.Equal(3, notifier.ReactionChanged.Count);   // add + remove + remove all fire an update
    }

    // ----- Edit -----

    [Fact]
    public async Task Edit_NotOwnMessage_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "theirs"); convs.Messages.Add(m);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.EditMessageAsync(conv.Id, m.Id, "hacked"));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task Edit_WithinWindow_UpdatesBody_SetsEditedAt_FiresEdited()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "typo", DateTime.UtcNow.AddMinutes(-1)); convs.Messages.Add(m);

        var dto = await sut.EditMessageAsync(conv.Id, m.Id, "  fixed  ");

        Assert.Equal("fixed", dto.Body);       // trimmed
        Assert.NotNull(dto.EditedAt);
        Assert.Equal("fixed", m.Body);
        var evt = Assert.Single(notifier.Edited);
        Assert.Equal(m.Id, evt.message.Id);
    }

    [Fact]
    public async Task Edit_OutsideWindow_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "old", DateTime.UtcNow - ChatService.EditWindow - TimeSpan.FromMinutes(1));
        convs.Messages.Add(m);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.EditMessageAsync(conv.Id, m.Id, "late"));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task Edit_DeletedMessage_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "gone", DateTime.UtcNow, deletedAt: DateTime.UtcNow); convs.Messages.Add(m);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.EditMessageAsync(conv.Id, m.Id, "revive"));
        Assert.Equal(403, ex.StatusCode);
    }

    // ----- Pin -----

    [Fact]
    public async Task Pin_AnyParticipant_CanPinEitherPartysMessage_FiresPinChanged()
    {
        var (sut, convs, _, notifier) = Build();   // caller = Me
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var theirs = Msg(conv.Id, Other, "their message"); convs.Messages.Add(theirs);

        await sut.PinAsync(conv.Id, theirs.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours });

        Assert.NotNull(theirs.PinnedAt);
        Assert.Equal(Me, theirs.PinnedByUserId);       // pinning is conversation-scoped, not ownership
        var evt = Assert.Single(notifier.PinChanged);
        Assert.True(evt.isPinned);
        Assert.Equal(theirs.Id, evt.messageId);
    }

    [Fact]
    public async Task Pin_BeyondCap_Throws409()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        for (var i = 0; i < ChatService.MaxPinnedPerConversation; i++)
        {
            var pinned = Msg(conv.Id, Me, $"pinned {i}");
            pinned.PinnedAt = DateTime.UtcNow; pinned.PinnedByUserId = Me;
            convs.Messages.Add(pinned);
        }
        var one = Msg(conv.Id, Me, "one too many"); convs.Messages.Add(one);

        var ex = await Assert.ThrowsAsync<ConflictException>(
            () => sut.PinAsync(conv.Id, one.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours }));
        Assert.Equal(409, ex.StatusCode);
        Assert.Contains("Pin limit", ex.Message);
    }

    [Fact]
    public async Task Unpin_ClearsPinFields_FiresPinChangedFalse()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "pinned");
        m.PinnedAt = DateTime.UtcNow; m.PinnedByUserId = Other;
        m.PinExpiresAt = DateTime.UtcNow.AddDays(7);
        convs.Messages.Add(m);

        await sut.UnpinAsync(conv.Id, m.Id);

        Assert.Null(m.PinnedAt);
        Assert.Null(m.PinnedByUserId);
        Assert.Null(m.PinExpiresAt);   // cleared by unpin
        Assert.False(Assert.Single(notifier.PinChanged).isPinned);
    }

    [Fact]
    public async Task GetPinned_ReturnsOnlyPinned()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var pinned = Msg(conv.Id, Me, "keep"); pinned.PinnedAt = DateTime.UtcNow; pinned.PinnedByUserId = Me;
        convs.Messages.Add(pinned);
        convs.Messages.Add(Msg(conv.Id, Me, "unpinned"));

        var list = await sut.GetPinnedAsync(conv.Id);

        Assert.Equal(pinned.Id, Assert.Single(list).Id);
    }

    // ----- Delete for everyone -----

    [Fact]
    public async Task DeleteEveryone_NotOwn_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var theirs = Msg(conv.Id, Other, "theirs"); convs.Messages.Add(theirs);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.DeleteForEveryoneAsync(conv.Id, theirs.Id));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task DeleteEveryone_OwnWithinWindow_SetsTombstone_FiresDeleted()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "oops"); convs.Messages.Add(m);

        await sut.DeleteForEveryoneAsync(conv.Id, m.Id);

        Assert.NotNull(m.DeletedAt);
        var evt = Assert.Single(notifier.Deleted);
        Assert.Equal(m.Id, evt.messageId);
    }

    [Fact]
    public async Task DeleteEveryone_OutsideWindow_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "ancient", DateTime.UtcNow - ChatService.DeleteForEveryoneWindow - TimeSpan.FromHours(1));
        convs.Messages.Add(m);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.DeleteForEveryoneAsync(conv.Id, m.Id));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task DeleteEveryone_AlreadyDeleted_IsIdempotentNoOp()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "gone", DateTime.UtcNow, deletedAt: DateTime.UtcNow.AddMinutes(-1));
        convs.Messages.Add(m);

        await sut.DeleteForEveryoneAsync(conv.Id, m.Id);   // no throw

        Assert.Empty(notifier.Deleted);   // no-op: nothing changed, no event
    }

    [Fact]
    public async Task DeleteEveryone_TombstoneBodyBlanked_InMessagePage()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "secret text"); convs.Messages.Add(m);

        await sut.DeleteForEveryoneAsync(conv.Id, m.Id);

        var page = await sut.GetMessagesAsync(conv.Id, null, 30);
        var row = Assert.Single(page.Items);
        Assert.True(row.IsDeleted);
        Assert.Equal(string.Empty, row.Body);   // original text never leaks
    }

    // ----- Delete for me -----

    [Fact]
    public async Task DeleteForMe_ExcludesFromMyPage_OtherPartyUnaffected_FiresNoEvent()
    {
        var (sut, convs, _, notifier) = Build();   // caller = Me
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "hide me"); convs.Messages.Add(m);

        await sut.DeleteForMeAsync(conv.Id, m.Id);

        // Gone from MY page…
        Assert.Empty((await sut.GetMessagesAsync(conv.Id, null, 30)).Items);

        // …but the other participant still sees it unchanged.
        var otherSvc = new ChatService(convs, new FakeUserRepository(), notifier,
            new FakeCurrentUser { UserId = Other }, new FakeMediaStorageService(), NullLogger<ChatService>.Instance);
        var theirPage = await otherSvc.GetMessagesAsync(conv.Id, null, 30);
        Assert.Equal("hide me", Assert.Single(theirPage.Items).Body);

        // Private to me — no realtime event at all.
        Assert.Empty(notifier.Deleted);
    }

    [Fact]
    public async Task DeleteForMe_AnyMessage_OwnOrNot_AndIdempotent()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var mine = Msg(conv.Id, Me, "mine"); convs.Messages.Add(mine);

        await sut.DeleteForMeAsync(conv.Id, mine.Id);   // own message — allowed, no window
        await sut.DeleteForMeAsync(conv.Id, mine.Id);   // again — idempotent no-op

        Assert.Single(convs.Deletions);
    }

    // ----- Forward -----

    [Fact]
    public async Task Forward_NotParticipantInTarget_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var source = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(source);
        var m = Msg(source.Id, Me, "share this"); convs.Messages.Add(m);
        var target = Conv(Other, Third, ConversationStatus.Accepted);   // Me not in target
        convs.Conversations.Add(target);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = [m.Id] }));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task Forward_CreatesMessages_WithForwardedFrom_PreservesOrder()
    {
        var (sut, convs, _, _) = Build();
        var source = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(source);
        var m1 = Msg(source.Id, Other, "first"); var m2 = Msg(source.Id, Other, "second");
        convs.Messages.Add(m1); convs.Messages.Add(m2);
        var target = Conv(Me, Third, ConversationStatus.Accepted);
        convs.Conversations.Add(target);

        var results = await sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = [m2.Id, m1.Id] });

        // Order preserved as requested (m2 then m1).
        Assert.Equal(new[] { "second", "first" }, results.Select(r => r.Body).ToArray());
        Assert.All(results, r => Assert.True(r.IsForwarded));
        Assert.All(results, r => Assert.Equal(target.Id, r.ConversationId));

        var forwarded = convs.Messages.Where(x => x.ConversationId == target.Id).ToList();
        Assert.Equal(2, forwarded.Count);
        Assert.All(forwarded, f => Assert.NotNull(f.ForwardedFromMessageId));
    }

    [Fact]
    public async Task Forward_IntoPending_BlockedByRuleC_WhenInitiatorAlreadyMessaged()
    {
        var (sut, convs, _, _) = Build();   // caller = Me
        var source = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(source);
        var m = Msg(source.Id, Other, "to forward"); convs.Messages.Add(m);

        // Target is a pending request I initiated and already spent my one message on.
        var target = Conv(Me, Third, ConversationStatus.Pending);
        convs.Conversations.Add(target);
        convs.Messages.Add(Msg(target.Id, Me, "my one request message"));

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = [m.Id] }));
        Assert.Equal(403, ex.StatusCode);
        // The atomic pre-flight refuses this (allowance already spent) before any write; its message
        // is the "one message" request-limit wording, not SendCoreAsync's "already sent".
        Assert.Contains("one message", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Forward_MultipleIntoPending_AtLimit_Refused_ZeroCreated()
    {
        var (sut, convs, _, _) = Build();   // caller = Me
        var source = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(source);
        var m1 = Msg(source.Id, Other, "one"); var m2 = Msg(source.Id, Other, "two");
        convs.Messages.Add(m1); convs.Messages.Add(m2);

        // Target is a fresh pending request I initiated — allowance is a SINGLE message. A 2-message
        // forward exceeds it, so the whole batch must be refused before anything is written.
        var target = Conv(Me, Third, ConversationStatus.Pending);
        convs.Conversations.Add(target);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(() => sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = [m1.Id, m2.Id] }));
        Assert.Equal(403, ex.StatusCode);
        Assert.Contains("one message", ex.Message, StringComparison.OrdinalIgnoreCase);

        // Atomic: NOTHING was delivered into the target.
        Assert.Empty(convs.Messages.Where(x => x.ConversationId == target.Id));
    }

    [Fact]
    public async Task Forward_SingleIntoPending_WithAllowanceRemaining_Succeeds()
    {
        var (sut, convs, _, _) = Build();   // caller = Me
        var source = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(source);
        var m = Msg(source.Id, Other, "share"); convs.Messages.Add(m);

        // Fresh pending request I initiated: I have not spent my one message yet.
        var target = Conv(Me, Third, ConversationStatus.Pending);
        convs.Conversations.Add(target);

        var results = await sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = [m.Id] });

        var forwarded = Assert.Single(results);
        Assert.True(forwarded.IsForwarded);
        Assert.Equal(target.Id, forwarded.ConversationId);
        Assert.Single(convs.Messages.Where(x => x.ConversationId == target.Id));
    }

    [Fact]
    public async Task Forward_BadSourceId_InAnyPosition_RefusesWholeBatch_ZeroCreated()
    {
        var (sut, convs, _, _) = Build();
        var source = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(source);
        var m1 = Msg(source.Id, Other, "first"); var m2 = Msg(source.Id, Other, "second");
        convs.Messages.Add(m1); convs.Messages.Add(m2);
        var target = Conv(Me, Third, ConversationStatus.Accepted);   // accepted → no rule (c) limit
        convs.Conversations.Add(target);

        // A non-existent id sits in the LAST position; the valid ones precede it. Old behaviour would
        // have delivered m1 & m2 before throwing — the pre-flight refuses the whole batch first.
        var ghost = Guid.NewGuid();
        var ex = await Assert.ThrowsAsync<NotFoundException>(() => sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = [m1.Id, m2.Id, ghost] }));
        Assert.Equal(404, ex.StatusCode);

        Assert.Empty(convs.Messages.Where(x => x.ConversationId == target.Id));
    }

    // ----- Reply (no new endpoint — via SendMessageRequestDto.ReplyToMessageId) -----

    [Fact]
    public async Task Send_WithReplyTo_SameConversation_PopulatesReplyTo()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var target = Msg(conv.Id, Other, "the original"); convs.Messages.Add(target);

        var dto = await sut.SendMessageAsync(conv.Id,
            new SendMessageRequestDto { Body = "replying", ReplyToMessageId = target.Id });

        Assert.NotNull(dto.ReplyTo);
        Assert.Equal(target.Id, dto.ReplyTo!.MessageId);
        Assert.Equal("the original", dto.ReplyTo.BodySnippet);
    }

    [Fact]
    public async Task Send_ReplyTo_CrossConversation_Throws400()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        var otherConv = Conv(Me, Third, ConversationStatus.Accepted);
        convs.Conversations.Add(conv); convs.Conversations.Add(otherConv);
        var foreign = Msg(otherConv.Id, Third, "in another thread"); convs.Messages.Add(foreign);

        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.SendMessageAsync(conv.Id,
            new SendMessageRequestDto { Body = "reply", ReplyToMessageId = foreign.Id }));
        Assert.Equal(400, ex.StatusCode);
    }

    // ----- Pin: duration & expiry -----

    [Fact]
    public async Task Pin_24Hours_SetsCorrectExpiry()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "msg"); convs.Messages.Add(m);

        var before = DateTime.UtcNow;
        await sut.PinAsync(conv.Id, m.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours });
        var after = DateTime.UtcNow;

        Assert.NotNull(m.PinExpiresAt);
        Assert.InRange(m.PinExpiresAt!.Value,
            before + ChatService.PinWindow24Hours,
            after  + ChatService.PinWindow24Hours);
    }

    [Fact]
    public async Task Pin_7Days_SetsCorrectExpiry()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "msg"); convs.Messages.Add(m);

        var before = DateTime.UtcNow;
        await sut.PinAsync(conv.Id, m.Id, new PinMessageRequestDto { Duration = PinDuration.SevenDays });
        var after = DateTime.UtcNow;

        Assert.NotNull(m.PinExpiresAt);
        Assert.InRange(m.PinExpiresAt!.Value,
            before + ChatService.PinWindow7Days,
            after  + ChatService.PinWindow7Days);
    }

    [Fact]
    public async Task Pin_30Days_SetsCorrectExpiry()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "msg"); convs.Messages.Add(m);

        var before = DateTime.UtcNow;
        await sut.PinAsync(conv.Id, m.Id, new PinMessageRequestDto { Duration = PinDuration.ThirtyDays });
        var after = DateTime.UtcNow;

        Assert.NotNull(m.PinExpiresAt);
        Assert.InRange(m.PinExpiresAt!.Value,
            before + ChatService.PinWindow30Days,
            after  + ChatService.PinWindow30Days);
    }

    [Fact]
    public async Task GetPinned_ExpiredPin_ExcludedFromList()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "will expire");
        m.PinnedAt = DateTime.UtcNow.AddHours(-25); m.PinnedByUserId = Me;
        m.PinExpiresAt = DateTime.UtcNow.AddHours(-1);  // already past
        convs.Messages.Add(m);

        Assert.Empty(await sut.GetPinnedAsync(conv.Id));
    }

    [Fact]
    public async Task Pin_ExpiredPins_NotCountedAgainstCap()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        for (var i = 0; i < ChatService.MaxPinnedPerConversation; i++)
        {
            var expired = Msg(conv.Id, Me, $"expired {i}");
            expired.PinnedAt = DateTime.UtcNow.AddDays(-2); expired.PinnedByUserId = Me;
            expired.PinExpiresAt = DateTime.UtcNow.AddHours(-1);
            convs.Messages.Add(expired);
        }
        var fresh = Msg(conv.Id, Me, "fresh"); convs.Messages.Add(fresh);

        await sut.PinAsync(conv.Id, fresh.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours });

        Assert.NotNull(fresh.PinnedAt);  // no 409 — expired pins did not count
    }

    [Fact]
    public async Task GetMessages_ExpiredPin_IsPinnedFalse()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "was pinned");
        m.PinnedAt = DateTime.UtcNow.AddHours(-25); m.PinnedByUserId = Me;
        m.PinExpiresAt = DateTime.UtcNow.AddHours(-1);
        convs.Messages.Add(m);

        var page = await sut.GetMessagesAsync(conv.Id, null, 30);
        Assert.False(Assert.Single(page.Items).IsPinned);
    }

    [Fact]
    public async Task Pin_UpdatesLastMessageAt()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "msg"); convs.Messages.Add(m);
        Assert.Null(conv.LastMessageAt);

        var before = DateTime.UtcNow;
        await sut.PinAsync(conv.Id, m.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours });

        Assert.NotNull(conv.LastMessageAt);
        Assert.True(conv.LastMessageAt >= before);
    }

    // ----- Pin: cap 4 + replace-oldest -----

    [Fact]
    public async Task Pin_ReplaceOldest_False_AtCap_Throws409()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        for (var i = 0; i < ChatService.MaxPinnedPerConversation; i++)
        {
            var p = Msg(conv.Id, Me, $"pinned {i}");
            p.PinnedAt = DateTime.UtcNow; p.PinnedByUserId = Me;
            convs.Messages.Add(p);
        }
        var extra = Msg(conv.Id, Me, "extra"); convs.Messages.Add(extra);

        var ex = await Assert.ThrowsAsync<ConflictException>(
            () => sut.PinAsync(conv.Id, extra.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours, ReplaceOldest = false }));
        Assert.Equal(409, ex.StatusCode);
        Assert.Contains("Pin limit", ex.Message);
    }

    [Fact]
    public async Task Pin_ReplaceOldest_True_AtCap_UnpinsOldestAndPinsNew()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);

        var oldest = Msg(conv.Id, Me, "oldest");
        oldest.PinnedAt = DateTime.UtcNow.AddHours(-4); oldest.PinnedByUserId = Me;
        convs.Messages.Add(oldest);
        for (var i = 0; i < ChatService.MaxPinnedPerConversation - 1; i++)
        {
            var p = Msg(conv.Id, Me, $"newer {i}");
            p.PinnedAt = DateTime.UtcNow.AddHours(-3 + i); p.PinnedByUserId = Me;
            convs.Messages.Add(p);
        }
        var newMsg = Msg(conv.Id, Other, "replacement"); convs.Messages.Add(newMsg);

        await sut.PinAsync(conv.Id, newMsg.Id,
            new PinMessageRequestDto { Duration = PinDuration.SevenDays, ReplaceOldest = true });

        Assert.Null(oldest.PinnedAt);       // oldest was unpinned
        Assert.Null(oldest.PinExpiresAt);   // expiry cleared too
        Assert.NotNull(newMsg.PinnedAt);    // new one pinned
        Assert.Equal(ChatService.MaxPinnedPerConversation,
            await convs.CountPinnedAsync(conv.Id));   // still at cap
        Assert.Equal(2, notifier.PinChanged.Count);   // unpin + pin
        var sysMsgs = convs.Messages.Where(m => m.Type == MessageType.System).ToList();
        Assert.Equal(2, sysMsgs.Count);   // MessageUnpinned + MessagePinned system rows
    }

    [Fact]
    public async Task Pin_Repin_UpdatesDuration_NoCapImpact_NoNewSystemMessage()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "msg"); convs.Messages.Add(m);

        await sut.PinAsync(conv.Id, m.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours });
        var sysCountAfterFirst = convs.Messages.Count(x => x.Type == MessageType.System);

        // Re-pin: changes duration only, no cap check, no new system message
        await sut.PinAsync(conv.Id, m.Id, new PinMessageRequestDto { Duration = PinDuration.ThirtyDays });

        Assert.NotNull(m.PinExpiresAt);
        // PinExpiresAt should now reflect ~30 days, not ~24 hours
        Assert.True(m.PinExpiresAt > DateTime.UtcNow + ChatService.PinWindow24Hours);
        // No additional system message created for re-pin
        Assert.Equal(sysCountAfterFirst, convs.Messages.Count(x => x.Type == MessageType.System));
    }

    // ----- System messages -----

    [Fact]
    public async Task Pin_CreatesSystemMessage_PinnedEvent()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "the message"); convs.Messages.Add(m);

        await sut.PinAsync(conv.Id, m.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours });

        var sysMsg = Assert.Single(convs.Messages.Where(x => x.Type == MessageType.System));
        Assert.Equal(SystemEventType.MessagePinned, sysMsg.SystemEventType);
        Assert.Equal(m.Id, sysMsg.SystemTargetMessageId);
        Assert.Equal(Me, sysMsg.SenderId);
        Assert.Equal(string.Empty, sysMsg.Body);
        Assert.Single(notifier.MessageReceived);   // system msg fanned out via MessageReceived
    }

    [Fact]
    public async Task Unpin_CreatesSystemMessage_UnpinnedEvent()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "was pinned");
        m.PinnedAt = DateTime.UtcNow; m.PinnedByUserId = Me;
        convs.Messages.Add(m);

        await sut.UnpinAsync(conv.Id, m.Id);

        var sysMsg = Assert.Single(convs.Messages.Where(x => x.Type == MessageType.System));
        Assert.Equal(SystemEventType.MessageUnpinned, sysMsg.SystemEventType);
        Assert.Equal(m.Id, sysMsg.SystemTargetMessageId);
        Assert.Equal(Me, sysMsg.SenderId);
        Assert.Single(notifier.MessageReceived);
    }

    [Fact]
    public async Task Pin_SystemMessage_Throws400()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "original"); convs.Messages.Add(m);
        convs.Messages.Add(SysMsg(conv.Id, Other, SystemEventType.MessagePinned, m.Id));

        var sys = convs.Messages.Last();
        var ex = await Assert.ThrowsAsync<ValidationException>(
            () => sut.PinAsync(conv.Id, sys.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours }));
        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task React_SystemMessage_Throws400()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "original"); convs.Messages.Add(m);
        convs.Messages.Add(SysMsg(conv.Id, Other, SystemEventType.MessagePinned, m.Id));

        var sys = convs.Messages.Last();
        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.ReactAsync(conv.Id, sys.Id, "👍"));
        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task Edit_SystemMessage_Throws400()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "original"); convs.Messages.Add(m);
        convs.Messages.Add(SysMsg(conv.Id, Me, SystemEventType.MessagePinned, m.Id));

        var sys = convs.Messages.Last();
        var ex = await Assert.ThrowsAsync<ValidationException>(
            () => sut.EditMessageAsync(conv.Id, sys.Id, "hacked"));
        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task Forward_SystemMessage_Throws400()
    {
        var (sut, convs, _, _) = Build();
        var source = Conv(Me, Other, ConversationStatus.Accepted); convs.Conversations.Add(source);
        var m = Msg(source.Id, Other, "original"); convs.Messages.Add(m);
        convs.Messages.Add(SysMsg(source.Id, Other, SystemEventType.MessagePinned, m.Id));
        var target = Conv(Me, Third, ConversationStatus.Accepted); convs.Conversations.Add(target);

        var sys = convs.Messages.Last();
        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.ForwardAsync(source.Id,
            new ForwardMessagesRequestDto { TargetConversationId = target.Id, MessageIds = [sys.Id] }));
        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task Send_ReplyToSystemMessage_Throws400()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted); convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "original"); convs.Messages.Add(m);
        convs.Messages.Add(SysMsg(conv.Id, Other, SystemEventType.MessagePinned, m.Id));

        var sys = convs.Messages.Last();
        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.SendMessageAsync(conv.Id,
            new SendMessageRequestDto { Body = "reply", ReplyToMessageId = sys.Id }));
        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task DeleteForMe_SystemMessage_IsAllowed()
    {
        var (sut, convs, _, notifier) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted); convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Other, "original"); convs.Messages.Add(m);
        convs.Messages.Add(SysMsg(conv.Id, Other, SystemEventType.MessagePinned, m.Id));

        var sys = convs.Messages.Last();
        await sut.DeleteForMeAsync(conv.Id, sys.Id);   // must not throw

        Assert.Single(convs.Deletions);
        Assert.Empty(notifier.Deleted);   // delete-for-me fires no realtime event
    }

    [Fact]
    public async Task DeleteForEveryone_SystemMessage_Throws403()
    {
        var (sut, convs, _, _) = Build();
        var conv = Conv(Me, Other, ConversationStatus.Accepted); convs.Conversations.Add(conv);
        var m = Msg(conv.Id, Me, "original"); convs.Messages.Add(m);
        convs.Messages.Add(SysMsg(conv.Id, Me, SystemEventType.MessagePinned, m.Id));

        var sys = convs.Messages.Last();
        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.DeleteForEveryoneAsync(conv.Id, sys.Id));
        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task GetConversations_SystemMessages_NotCountedAsUnread()
    {
        // Me pins Other's message → system msg has SenderId=Me.
        // From Other's perspective: real msg (SenderId=Other) is their own, system msg (SenderId=Me) would
        // inflate unread by 1 without the fix. With the fix it stays 0.
        var convs = new FakeConversationRepository();
        var users = new FakeUserRepository();
        var notifier = new RecordingChatNotifier();
        var conv = Conv(Me, Other, ConversationStatus.Accepted);
        convs.Conversations.Add(conv);
        var t0 = DateTime.UtcNow.AddMinutes(-5);
        var m = new Message { Id = Guid.NewGuid(), ConversationId = conv.Id, SenderId = Other, Body = "real", Type = MessageType.Text, CreatedAt = t0 };
        convs.Messages.Add(m);
        conv.LastMessageAt = t0;

        var meSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Me }, new FakeMediaStorageService(), NullLogger<ChatService>.Instance);
        var otherSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Other }, new FakeMediaStorageService(), NullLogger<ChatService>.Instance);

        await meSvc.PinAsync(conv.Id, m.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours });

        var page = await otherSvc.GetConversationsAsync(1, 20);
        Assert.Equal(0, Assert.Single(page.Items).UnreadCount);   // system msg excluded
    }

    [Fact]
    public async Task Pin_InPendingConversation_SystemMessageDoesNotConsumeRuleC()
    {
        var (sut, convs, _, _) = Build();   // caller = Me (initiator)
        var conv = Conv(Me, Other, ConversationStatus.Pending);
        convs.Conversations.Add(conv);

        // Me sends first (and only allowed) real message.
        await sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "first" });

        // Pin that message → creates system message with SenderId=Me.
        var firstMsg = convs.Messages.First(x => x.Type != MessageType.System);
        await sut.PinAsync(conv.Id, firstMsg.Id, new PinMessageRequestDto { Duration = PinDuration.TwentyFourHours });

        // Rule (c) still active — system message must NOT count against the 1-message allowance.
        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.SendMessageAsync(conv.Id, new SendMessageRequestDto { Body = "second" }));
        Assert.Equal(403, ex.StatusCode);
        Assert.Contains("already sent", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    // ===== Test doubles =====

    private sealed class FakeCurrentUser : ICurrentUserService
    {
        public Guid? UserId { get; set; }
        public string? Email => null;
        public string? Role => null;
        public bool IsIdentityVerified => false;
        public bool IsAuthenticated => UserId != null;
    }

    private sealed class RecordingChatNotifier : IChatNotifier
    {
        public readonly List<(List<Guid> userIds, MessageDto message)> MessageReceived = [];
        public readonly List<(Guid userId, ConversationSummaryDto conversation)> RequestReceived = [];
        public readonly List<(Guid userId, Guid conversationId)> Accepted = [];
        public readonly List<(List<Guid> userIds, Guid conversationId, Guid messageId, List<MessageReactionSummaryDto> reactions)> ReactionChanged = [];
        public readonly List<(List<Guid> userIds, MessageDto message)> Edited = [];
        public readonly List<(List<Guid> userIds, Guid conversationId, Guid messageId)> Deleted = [];
        public readonly List<(List<Guid> userIds, Guid conversationId, Guid messageId, bool isPinned, DateTime? pinExpiresAt)> PinChanged = [];
        public readonly List<(Guid userId, Guid conversationId, DateTime lastReadAt)> ConversationRead = [];
        public readonly List<(Guid userId, Guid conversationId, Guid messageId)> Played = [];
        public bool Throw;

        public Task MessageReceivedAsync(IEnumerable<Guid> userIds, MessageDto message, CancellationToken ct = default)
        {
            if (Throw) throw new InvalidOperationException("notifier down");
            MessageReceived.Add((userIds.ToList(), message));
            return Task.CompletedTask;
        }

        public Task ConversationRequestReceivedAsync(Guid userId, ConversationSummaryDto conversation, CancellationToken ct = default)
        {
            if (Throw) throw new InvalidOperationException("notifier down");
            RequestReceived.Add((userId, conversation));
            return Task.CompletedTask;
        }

        public Task ConversationAcceptedAsync(Guid userId, Guid conversationId, CancellationToken ct = default)
        {
            if (Throw) throw new InvalidOperationException("notifier down");
            Accepted.Add((userId, conversationId));
            return Task.CompletedTask;
        }

        public Task ReactionChangedAsync(IEnumerable<Guid> userIds, Guid conversationId, Guid messageId,
            IReadOnlyList<MessageReactionSummaryDto> reactions, CancellationToken ct = default)
        {
            if (Throw) throw new InvalidOperationException("notifier down");
            ReactionChanged.Add((userIds.ToList(), conversationId, messageId, reactions.ToList()));
            return Task.CompletedTask;
        }

        public Task MessageEditedAsync(IEnumerable<Guid> userIds, MessageDto message, CancellationToken ct = default)
        {
            if (Throw) throw new InvalidOperationException("notifier down");
            Edited.Add((userIds.ToList(), message));
            return Task.CompletedTask;
        }

        public Task MessageDeletedAsync(IEnumerable<Guid> userIds, Guid conversationId, Guid messageId, CancellationToken ct = default)
        {
            if (Throw) throw new InvalidOperationException("notifier down");
            Deleted.Add((userIds.ToList(), conversationId, messageId));
            return Task.CompletedTask;
        }

        public Task MessagePinChangedAsync(IEnumerable<Guid> userIds, Guid conversationId, Guid messageId,
            bool isPinned, DateTime? pinExpiresAt, CancellationToken ct = default)
        {
            if (Throw) throw new InvalidOperationException("notifier down");
            PinChanged.Add((userIds.ToList(), conversationId, messageId, isPinned, pinExpiresAt));
            return Task.CompletedTask;
        }

        public Task ConversationReadAsync(Guid userId, Guid conversationId, DateTime lastReadAt, CancellationToken ct = default)
        {
            if (Throw) throw new InvalidOperationException("notifier down");
            ConversationRead.Add((userId, conversationId, lastReadAt));
            return Task.CompletedTask;
        }

        public Task MessagePlayedAsync(Guid userId, Guid conversationId, Guid messageId, CancellationToken ct = default)
        {
            if (Throw) throw new InvalidOperationException("notifier down");
            Played.Add((userId, conversationId, messageId));
            return Task.CompletedTask;
        }
    }

    // In-memory Cloudinary stand-in — no network. Counts uploads/deletes so tests can prove a forward
    // does NOT re-upload and an unauthorized send never uploads. Duration is configurable for the
    // over-length video test.
    private sealed class FakeMediaStorageService : IMediaStorageService
    {
        public int ImageUploads;
        public int VideoUploads;
        public int AudioUploads;
        public int DocumentUploads;
        public readonly List<string> Deleted = [];
        public int? VideoDurationMs = 5_000;   // default 5 s — under the 120 s limit
        public int? AudioDurationMs = 8_000;   // default 8 s — under the 300 s limit

        public MediaUploadResult ImageResult { get; set; } = new()
        {
            SecureUrl = "https://res.cloudinary.com/x/image/upload/v1/skillora/chat/img.jpg",
            ThumbnailUrl = "https://res.cloudinary.com/x/image/upload/c_fill,w_400,q_auto/v1/skillora/chat/img.jpg",
            PublicId = "skillora/chat/img", Width = 800, Height = 600, DurationMs = null, Bytes = 1234
        };

        public Task<MediaUploadResult> UploadImageAsync(Stream content, string fileName, string folder, CancellationToken ct = default)
        {
            ImageUploads++;
            return Task.FromResult(ImageResult);
        }

        public Task<MediaUploadResult> UploadVideoAsync(Stream content, string fileName, string folder, CancellationToken ct = default)
        {
            VideoUploads++;
            return Task.FromResult(new MediaUploadResult
            {
                SecureUrl = "https://res.cloudinary.com/x/video/upload/v1/skillora/chat/vid.mp4",
                ThumbnailUrl = "https://res.cloudinary.com/x/video/upload/so_0,w_400,c_fill/v1/skillora/chat/vid.jpg",
                PublicId = "skillora/chat/vid", Width = 1280, Height = 720, DurationMs = VideoDurationMs, Bytes = 456789
            });
        }

        public Task<MediaUploadResult> UploadAudioAsync(Stream content, string fileName, string folder, CancellationToken ct = default)
        {
            AudioUploads++;
            return Task.FromResult(new MediaUploadResult
            {
                SecureUrl = "https://res.cloudinary.com/x/video/upload/v1/skillora/chat/voice.m4a",
                ThumbnailUrl = string.Empty,   // no poster for audio
                PublicId = "skillora/chat/voice", Width = 0, Height = 0, DurationMs = AudioDurationMs, Bytes = 34567
            });
        }

        public Task<MediaUploadResult> UploadDocumentAsync(Stream content, string fileName, string folder, CancellationToken ct = default)
        {
            DocumentUploads++;
            return Task.FromResult(new MediaUploadResult
            {
                SecureUrl = "https://res.cloudinary.com/x/raw/upload/v1/skillora/chat/doc.pdf",
                ThumbnailUrl = string.Empty,   // no poster for a document
                PublicId = "skillora/chat/doc", Width = 0, Height = 0, DurationMs = null, Bytes = 4096
            });
        }

        public Task DeleteAsync(string publicId, MediaKind kind, CancellationToken ct = default)
        {
            Deleted.Add(publicId);
            return Task.CompletedTask;
        }
    }

    private sealed class FakeUserRepository : IUserRepository
    {
        public readonly List<User> Users = [];
        public void Add(Guid id) => Users.Add(new User { Id = id, FullName = $"User {id:N}", Email = $"{id:N}@x.com" });

        public Task<User?> GetByIdAsync(Guid id) => Task.FromResult(Users.FirstOrDefault(u => u.Id == id));
        public Task<User?> GetByEmailAsync(string email) => Task.FromResult<User?>(null);
        public Task<User?> GetByExternalIdAsync(AuthProvider provider, string externalId) => Task.FromResult<User?>(null);
        public Task<bool> EmailExistsAsync(string email) => Task.FromResult(false);
        public Task AddAsync(User user) { Users.Add(user); return Task.CompletedTask; }
        public Task SaveChangesAsync() => Task.CompletedTask;
        public Task<Guid?> GetSecurityStampAsync(Guid userId) => Task.FromResult<Guid?>(null);
    }

    private sealed class FakeConversationRepository : IConversationRepository
    {
        public readonly List<Conversation> Conversations = [];
        public readonly List<Message> Messages = [];
        public readonly List<MessageReaction> Reactions = [];
        public readonly List<MessageDeletion> Deletions = [];
        public readonly List<MessagePlay> Plays = [];
        public readonly List<(Guid a, Guid b)> AcceptedConnections = [];
        public int LastMessageLimitRequested;

        public Task<Conversation?> GetByIdAsync(Guid id) =>
            Task.FromResult(Conversations.FirstOrDefault(c => c.Id == id));

        public Task<Conversation?> FindBetweenAsync(Guid userA, Guid userB) =>
            Task.FromResult(Conversations.FirstOrDefault(c =>
                c.Participants.Any(p => p.UserId == userA) && c.Participants.Any(p => p.UserId == userB)));

        public Task<bool> AreConnectedAsync(Guid userA, Guid userB, CancellationToken ct = default) =>
            Task.FromResult(AcceptedConnections.Any(x =>
                (x.a == userA && x.b == userB) || (x.a == userB && x.b == userA)));

        public Task AddAsync(Conversation conversation) { Conversations.Add(conversation); return Task.CompletedTask; }
        public Task AddMessageAsync(Message message) { Messages.Add(message); return Task.CompletedTask; }
        public Task SaveChangesAsync() => Task.CompletedTask;

        public Task<int> CountMessagesBySenderAsync(Guid conversationId, Guid senderId, CancellationToken ct = default) =>
            Task.FromResult(Messages.Count(m => m.ConversationId == conversationId && m.SenderId == senderId
                && m.Type != MessageType.System));

        public Task<IReadOnlyList<MessageDto>> GetMessagesAsync(Guid conversationId, Guid userId, DateTime? before, int limit, CancellationToken ct = default)
        {
            LastMessageLimitRequested = limit;
            // Mirror the real repo: include "delete for everyone" tombstones; exclude the caller's
            // "delete for me" rows.
            var q = Messages.Where(m => m.ConversationId == conversationId &&
                !Deletions.Any(d => d.MessageId == m.Id && d.UserId == userId));
            if (before.HasValue) q = q.Where(m => m.CreatedAt < before.Value);
            IReadOnlyList<MessageDto> rows = q
                .OrderByDescending(m => m.CreatedAt).ThenByDescending(m => m.Id)
                .Take(limit)
                .Select(m => BuildMessageDto(m, userId))
                .ToList();
            return Task.FromResult(rows);
        }

        // Mirrors ConversationRepository.ProjectMessage + AttachReactionsAsync for the fakes.
        private MessageDto BuildMessageDto(Message m, Guid userId)
        {
            var reactions = Reactions.Where(r => r.MessageId == m.Id)
                .GroupBy(r => r.Emoji)
                .Select(g => new MessageReactionSummaryDto
                {
                    Emoji = g.Key, Count = g.Count(), ReactedByMe = g.Any(x => x.UserId == userId)
                })
                .OrderByDescending(x => x.Count)
                .ToList();

            MessageReplyDto? replyTo = null;
            if (m.ReplyToMessageId != null)
            {
                var r = Messages.FirstOrDefault(x => x.Id == m.ReplyToMessageId);
                if (r != null)
                    replyTo = new MessageReplyDto
                    {
                        MessageId = r.Id,
                        SenderId = r.SenderId,
                        SenderName = string.Empty,
                        BodySnippet = r.DeletedAt != null ? string.Empty
                            : (r.Body.Length > 80 ? r.Body.Substring(0, 80) : r.Body),
                        Type = r.Type,
                        FileName = r.DeletedAt != null ? null : r.MediaFileName,
                        IsDeleted = r.DeletedAt != null
                    };
            }

            return new MessageDto
            {
                Id = m.Id,
                ConversationId = m.ConversationId,
                SenderId = m.SenderId,
                Body = m.DeletedAt == null ? m.Body : string.Empty,
                Type = m.Type,
                CreatedAt = m.CreatedAt,
                IsDeleted = m.DeletedAt != null,
                EditedAt = m.EditedAt,
                IsPinned = m.PinnedAt != null && (m.PinExpiresAt == null || m.PinExpiresAt > DateTime.UtcNow),
                PinnedByUserId = m.PinnedByUserId,
                PinExpiresAt = m.PinExpiresAt,
                SystemEventType = m.SystemEventType,
                SystemTargetMessageId = m.SystemTargetMessageId,
                IsForwarded = m.ForwardedFromMessageId != null,
                // Media (mirrors ProjectMessage): URLs blanked for a tombstone, dimensions kept.
                MediaUrl = m.DeletedAt == null ? m.MediaUrl : null,
                MediaThumbnailUrl = m.DeletedAt == null ? m.MediaThumbnailUrl : null,
                MediaWidth = m.MediaWidth,
                MediaHeight = m.MediaHeight,
                MediaDurationMs = m.MediaDurationMs,
                MediaMimeType = m.MediaMimeType,
                MediaFileName = m.DeletedAt == null ? m.MediaFileName : null,
                MediaWaveform = m.DeletedAt == null ? m.MediaWaveform : null,
                // Played flags mirror ProjectMessage: caller-relative EXISTS, blanked for a tombstone.
                PlayedByMe = m.DeletedAt == null && Plays.Any(p => p.MessageId == m.Id && p.UserId == userId),
                PlayedByOther = m.DeletedAt == null && Plays.Any(p => p.MessageId == m.Id && p.UserId != userId),
                ReplyTo = replyTo,
                Reactions = reactions
            };
        }

        public Task<Message?> GetMessageByIdAsync(Guid messageId) =>
            Task.FromResult(Messages.FirstOrDefault(m => m.Id == messageId));

        public Task<MessageDto?> GetMessageDtoAsync(Guid messageId, Guid userId, CancellationToken ct = default)
        {
            var m = Messages.FirstOrDefault(x => x.Id == messageId);
            return Task.FromResult(m == null ? null : BuildMessageDto(m, userId));
        }

        public Task<IReadOnlyList<Message>> GetMessagesByIdsAsync(Guid conversationId, IReadOnlyCollection<Guid> ids, CancellationToken ct = default)
        {
            IReadOnlyList<Message> rows = Messages
                .Where(m => m.ConversationId == conversationId && ids.Contains(m.Id))
                .ToList();
            return Task.FromResult(rows);
        }

        public Task<IReadOnlyList<MessageDto>> GetPinnedAsync(Guid conversationId, Guid userId, CancellationToken ct = default)
        {
            IReadOnlyList<MessageDto> rows = Messages
                .Where(m => m.ConversationId == conversationId && m.PinnedAt != null &&
                    (m.PinExpiresAt == null || m.PinExpiresAt > DateTime.UtcNow) &&
                    !Deletions.Any(d => d.MessageId == m.Id && d.UserId == userId))
                .OrderByDescending(m => m.PinnedAt)
                .Select(m => BuildMessageDto(m, userId))
                .ToList();
            return Task.FromResult(rows);
        }

        public Task<int> CountPinnedAsync(Guid conversationId, CancellationToken ct = default) =>
            Task.FromResult(Messages.Count(m => m.ConversationId == conversationId && m.PinnedAt != null &&
                (m.PinExpiresAt == null || m.PinExpiresAt > DateTime.UtcNow)));

        public Task<Message?> GetOldestActivePinAsync(Guid conversationId, CancellationToken ct = default) =>
            Task.FromResult(Messages
                .Where(m => m.ConversationId == conversationId && m.PinnedAt != null &&
                    (m.PinExpiresAt == null || m.PinExpiresAt > DateTime.UtcNow) &&
                    m.Type != MessageType.System)
                .OrderBy(m => m.PinnedAt)
                .FirstOrDefault());

        public Task<MessageReaction?> GetReactionAsync(Guid messageId, Guid userId) =>
            Task.FromResult(Reactions.FirstOrDefault(r => r.MessageId == messageId && r.UserId == userId));

        public Task AddReactionAsync(MessageReaction reaction) { Reactions.Add(reaction); return Task.CompletedTask; }
        public Task RemoveReactionAsync(MessageReaction reaction) { Reactions.Remove(reaction); return Task.CompletedTask; }

        public Task<IReadOnlyList<MessageReactionSummaryDto>> GetReactionSummaryAsync(Guid messageId, Guid? me, CancellationToken ct = default)
        {
            IReadOnlyList<MessageReactionSummaryDto> rows = Reactions
                .Where(r => r.MessageId == messageId)
                .GroupBy(r => r.Emoji)
                .Select(g => new MessageReactionSummaryDto
                {
                    Emoji = g.Key, Count = g.Count(), ReactedByMe = me.HasValue && g.Any(x => x.UserId == me.Value)
                })
                .OrderByDescending(x => x.Count)
                .ToList();
            return Task.FromResult(rows);
        }

        public Task AddMessageDeletionAsync(MessageDeletion deletion) { Deletions.Add(deletion); return Task.CompletedTask; }
        public Task<bool> HasMessageDeletionAsync(Guid messageId, Guid userId, CancellationToken ct = default) =>
            Task.FromResult(Deletions.Any(d => d.MessageId == messageId && d.UserId == userId));

        public Task AddMessagePlayAsync(MessagePlay play) { Plays.Add(play); return Task.CompletedTask; }
        public Task<bool> HasMessagePlayAsync(Guid messageId, Guid userId, CancellationToken ct = default) =>
            Task.FromResult(Plays.Any(p => p.MessageId == messageId && p.UserId == userId));

        public Task<ConversationSummaryDto?> GetSummaryByIdAsync(Guid conversationId, Guid userId, CancellationToken ct = default)
        {
            var c = Conversations.FirstOrDefault(x => x.Id == conversationId && x.Participants.Any(p => p.UserId == userId));
            return Task.FromResult(c == null ? null : BuildSummary(c, userId));
        }

        // Mirrors the real repo: message-less conversations (LastMessageAt == null) are excluded from lists.
        public Task<PagedResult<ConversationSummaryDto>> GetAcceptedPageAsync(Guid userId, int page, int pageSize, CancellationToken ct = default) =>
            Page(userId, page, pageSize, c => c.Status == ConversationStatus.Accepted && c.LastMessageAt != null && c.Participants.Any(p => p.UserId == userId));

        public Task<PagedResult<ConversationSummaryDto>> GetPendingRequestsPageAsync(Guid userId, int page, int pageSize, CancellationToken ct = default) =>
            Page(userId, page, pageSize, c => c.Status == ConversationStatus.Pending && c.InitiatorId != userId && c.LastMessageAt != null && c.Participants.Any(p => p.UserId == userId));

        private Task<PagedResult<ConversationSummaryDto>> Page(Guid userId, int page, int pageSize, Func<Conversation, bool> pred)
        {
            var all = Conversations.Where(pred)
                .OrderByDescending(c => c.LastMessageAt)   // mirrors real repo: plain LastMessageAt, non-null by predicate
                .ToList();
            var items = all.Skip((page - 1) * pageSize).Take(pageSize).Select(c => BuildSummary(c, userId)!).ToList();
            return Task.FromResult(new PagedResult<ConversationSummaryDto>
            {
                Items = items, Page = page, PageSize = pageSize, TotalCount = all.Count
            });
        }

        private ConversationSummaryDto BuildSummary(Conversation c, Guid userId)
        {
            var otherPart = c.Participants.First(p => p.UserId != userId);
            var otherId = otherPart.UserId;
            var myPart = c.Participants.First(p => p.UserId == userId);
            var last = Messages.Where(m => m.ConversationId == c.Id && m.DeletedAt == null && m.Type != MessageType.System)
                .OrderByDescending(m => m.CreatedAt).ThenByDescending(m => m.Id).FirstOrDefault();
            var unread = Messages.Count(m => m.ConversationId == c.Id && m.SenderId != userId && m.DeletedAt == null
                && m.Type != MessageType.System
                && (myPart.LastReadAt == null || m.CreatedAt > myPart.LastReadAt));
            return new ConversationSummaryDto
            {
                Id = c.Id,
                Status = c.Status,
                IsRequest = c.Status == ConversationStatus.Pending && c.InitiatorId != userId,
                OtherUser = new ConversationUserDto { UserId = otherId },
                LastMessagePreview = last?.Body,
                LastMessageType = last?.Type,
                LastMessageAt = c.LastMessageAt,
                UnreadCount = unread,
                OtherLastReadAt = otherPart.LastReadAt   // caller-relative: the OTHER party's watermark
            };
        }
    }
}
