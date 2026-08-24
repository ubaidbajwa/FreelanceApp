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
        var convs = new FakeConversationRepository();
        var users = new FakeUserRepository();
        var notifier = new RecordingChatNotifier();
        var current = new FakeCurrentUser { UserId = caller ?? Me };
        var sut = new ChatService(convs, users, notifier, current, NullLogger<ChatService>.Instance);
        return (sut, convs, users, notifier);
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
            new FakeCurrentUser { UserId = Me }, NullLogger<ChatService>.Instance);
        var first = await meService.StartOrGetConversationAsync(Other);

        var otherService = new ChatService(convs, users, notifier,
            new FakeCurrentUser { UserId = Other }, NullLogger<ChatService>.Instance);
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

        var meSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Me }, NullLogger<ChatService>.Instance);
        var otherSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Other }, NullLogger<ChatService>.Instance);

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
            new FakeCurrentUser { UserId = Other }, NullLogger<ChatService>.Instance);
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

        var meSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Me }, NullLogger<ChatService>.Instance);
        var otherSvc = new ChatService(convs, users, notifier, new FakeCurrentUser { UserId = Other }, NullLogger<ChatService>.Instance);

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
            var otherId = c.Participants.First(p => p.UserId != userId).UserId;
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
                LastMessageAt = c.LastMessageAt,
                UnreadCount = unread
            };
        }
    }
}
