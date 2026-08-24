using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using FreelanceApp.Infrastructure.Repositories;
using Microsoft.EntityFrameworkCore;

namespace FreelanceApp.Tests.Messaging;

public class ConversationRepositoryTests
{
    // Fresh InMemory context per test — repo LINQ runs LINQ-to-objects, so the lateral join,
    // watermark unread count, last-message preview and ordering are all exercised faithfully.
    private static AppDbContext NewContext() =>
        new(new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);

    private static User AddUser(AppDbContext db, string name, string? headline = null, string? photo = null)
    {
        var u = new User { Id = Guid.NewGuid(), Email = $"{Guid.NewGuid():N}@x.com", FullName = name };
        db.Users.Add(u);
        db.Profiles.Add(new Profile
        {
            Id = Guid.NewGuid(), UserId = u.Id, DisplayName = name,
            Headline = headline, ProfilePhotoUrl = photo
        });
        return u;
    }

    private static Conversation AddConversation(
        AppDbContext db, Guid initiator, Guid other, ConversationStatus status, DateTime createdAt)
    {
        var c = new Conversation { Id = Guid.NewGuid(), Status = status, InitiatorId = initiator, CreatedAt = createdAt };
        db.Conversations.Add(c);
        db.ConversationParticipants.Add(new ConversationParticipant { ConversationId = c.Id, UserId = initiator, JoinedAt = createdAt });
        db.ConversationParticipants.Add(new ConversationParticipant { ConversationId = c.Id, UserId = other, JoinedAt = createdAt });
        return c;
    }

    private static void AddMessage(AppDbContext db, Guid convId, Guid sender, string body, DateTime at)
    {
        db.Messages.Add(new Message
        {
            Id = Guid.NewGuid(), ConversationId = convId, SenderId = sender,
            Body = body, Type = MessageType.Text, CreatedAt = at
        });
    }

    // ===== ACCEPTED LIST PROJECTION =====

    [Fact]
    public async Task GetAcceptedPage_ProjectsOtherParticipant_LastMessage_AndUnreadCount()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice", headline: "Designer", photo: "https://cdn/alice.jpg");

        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var conv = AddConversation(db, me.Id, alice.Id, ConversationStatus.Accepted, t0);
        AddMessage(db, conv.Id, me.Id, "hi", t0.AddMinutes(1));
        AddMessage(db, conv.Id, alice.Id, "hello", t0.AddMinutes(2));
        conv.LastMessageAt = t0.AddMinutes(2);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var page = await repo.GetAcceptedPageAsync(me.Id, 1, 20);

        var row = Assert.Single(page.Items);
        Assert.Equal(conv.Id, row.Id);
        Assert.False(row.IsRequest);   // accepted, not a pending request
        Assert.Equal(alice.Id, row.OtherUser.UserId);
        Assert.Equal("Alice", row.OtherUser.FullName);
        Assert.Equal("Designer", row.OtherUser.Headline);
        Assert.Equal("https://cdn/alice.jpg", row.OtherUser.PhotoUrl);
        Assert.Equal("hello", row.LastMessagePreview);
        Assert.Equal(1, row.UnreadCount);   // only Alice's message, unread (LastReadAt null)
    }

    [Fact]
    public async Task GetAcceptedPage_UnreadCount_RespectsReadWatermark()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");

        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var conv = AddConversation(db, me.Id, alice.Id, ConversationStatus.Accepted, t0);
        AddMessage(db, conv.Id, alice.Id, "one", t0.AddMinutes(1));
        AddMessage(db, conv.Id, alice.Id, "two", t0.AddMinutes(2));
        conv.LastMessageAt = t0.AddMinutes(2);
        await db.SaveChangesAsync();

        // Mark read up to the first message → only the second remains unread.
        var myPart = db.ConversationParticipants.Single(p => p.ConversationId == conv.Id && p.UserId == me.Id);
        myPart.LastReadAt = t0.AddMinutes(1);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var page = await repo.GetAcceptedPageAsync(me.Id, 1, 20);

        Assert.Equal(1, Assert.Single(page.Items).UnreadCount);
    }

    [Fact]
    public async Task GetAcceptedPage_ExcludesPendingConversations()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");
        var bob = AddUser(db, "Bob");

        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var accepted = AddConversation(db, me.Id, alice.Id, ConversationStatus.Accepted, t0);
        AddMessage(db, accepted.Id, me.Id, "hi", t0.AddMinutes(1));
        accepted.LastMessageAt = t0.AddMinutes(1);

        var pending = AddConversation(db, bob.Id, me.Id, ConversationStatus.Pending, t0.AddMinutes(2));
        AddMessage(db, pending.Id, bob.Id, "request", t0.AddMinutes(2));
        pending.LastMessageAt = t0.AddMinutes(2);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var page = await repo.GetAcceptedPageAsync(me.Id, 1, 20);

        Assert.Equal(accepted.Id, Assert.Single(page.Items).Id);
    }

    [Fact]
    public async Task GetAcceptedPage_LastMessagePreview_TruncatedTo120Chars()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");

        var longBody = new string('x', 200);
        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var conv = AddConversation(db, me.Id, alice.Id, ConversationStatus.Accepted, t0);
        AddMessage(db, conv.Id, alice.Id, longBody, t0.AddMinutes(1));
        conv.LastMessageAt = t0.AddMinutes(1);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var row = Assert.Single((await repo.GetAcceptedPageAsync(me.Id, 1, 20)).Items);

        Assert.Equal(120, row.LastMessagePreview!.Length);
        Assert.Equal(new string('x', 120), row.LastMessagePreview);
    }

    [Fact]
    public async Task GetAcceptedPage_ExcludesConversationsWithNoMessages()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");
        // Accepted thread that was opened but never messaged → LastMessageAt stays null.
        AddConversation(db, me.Id, alice.Id, ConversationStatus.Accepted, DateTime.UtcNow);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var page = await repo.GetAcceptedPageAsync(me.Id, 1, 20);

        Assert.Empty(page.Items);
        Assert.Equal(0, page.TotalCount);
    }

    // ===== OUTGOING PENDING (Fix 1): the sender's own request is their conversation =====

    [Fact]
    public async Task GetAcceptedPage_IncludesMyOwnPendingRequest_AsNonRequest()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");

        // I opened the thread and sent the request message — still Pending (Alice hasn't replied).
        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var mine = AddConversation(db, me.Id, alice.Id, ConversationStatus.Pending, t0);
        AddMessage(db, mine.Id, me.Id, "hello Alice", t0.AddMinutes(1));
        mine.LastMessageAt = t0.AddMinutes(1);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var page = await repo.GetAcceptedPageAsync(me.Id, 1, 20);

        var row = Assert.Single(page.Items);
        Assert.Equal(mine.Id, row.Id);
        Assert.False(row.IsRequest);   // I'm the initiator — this is my conversation, not a request to me
    }

    [Fact]
    public async Task GetPendingRequestsPage_ExcludesMyOwnPendingRequest()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");

        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var mine = AddConversation(db, me.Id, alice.Id, ConversationStatus.Pending, t0);
        AddMessage(db, mine.Id, me.Id, "hello Alice", t0.AddMinutes(1));
        mine.LastMessageAt = t0.AddMinutes(1);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var page = await repo.GetPendingRequestsPageAsync(me.Id, 1, 20);

        Assert.Empty(page.Items);   // my own outgoing request is never an incoming request to me
    }

    [Fact]
    public async Task RecipientView_OfMyPendingRequest_IsIncomingRequest_NotAccepted()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");

        // I sent Alice a pending request. Now look at the SAME conversation from Alice's side.
        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var conv = AddConversation(db, me.Id, alice.Id, ConversationStatus.Pending, t0);
        AddMessage(db, conv.Id, me.Id, "hello Alice", t0.AddMinutes(1));
        conv.LastMessageAt = t0.AddMinutes(1);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);

        var alicePending = await repo.GetPendingRequestsPageAsync(alice.Id, 1, 20);
        var pendingRow = Assert.Single(alicePending.Items);
        Assert.Equal(conv.Id, pendingRow.Id);
        Assert.True(pendingRow.IsRequest);   // to Alice, this is an incoming request

        var aliceAccepted = await repo.GetAcceptedPageAsync(alice.Id, 1, 20);
        Assert.Empty(aliceAccepted.Items);   // not in Alice's conversations until she accepts
    }

    [Fact]
    public async Task DeclinedConversation_AppearsInNeitherList_ForEitherParty()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");

        // I requested, Alice declined. The absence of a reply is how I learn — it must not linger.
        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var conv = AddConversation(db, me.Id, alice.Id, ConversationStatus.Declined, t0);
        AddMessage(db, conv.Id, me.Id, "hello Alice", t0.AddMinutes(1));
        conv.LastMessageAt = t0.AddMinutes(1);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);

        Assert.Empty((await repo.GetAcceptedPageAsync(me.Id, 1, 20)).Items);
        Assert.Empty((await repo.GetPendingRequestsPageAsync(me.Id, 1, 20)).Items);
        Assert.Empty((await repo.GetAcceptedPageAsync(alice.Id, 1, 20)).Items);
        Assert.Empty((await repo.GetPendingRequestsPageAsync(alice.Id, 1, 20)).Items);
    }

    [Fact]
    public async Task GetAcceptedPage_ExcludesMyOwnPendingRequest_WithNoMessages()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");
        // I opened a thread but never sent the message → LastMessageAt stays null, excluded everywhere.
        AddConversation(db, me.Id, alice.Id, ConversationStatus.Pending, DateTime.UtcNow);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);

        Assert.Empty((await repo.GetAcceptedPageAsync(me.Id, 1, 20)).Items);
        Assert.Empty((await repo.GetPendingRequestsPageAsync(me.Id, 1, 20)).Items);
    }

    // ===== PENDING REQUESTS LIST =====

    [Fact]
    public async Task GetPendingRequestsPage_ExcludesConversationsWithNoMessages()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var bob = AddUser(db, "Bob");
        // Pending thread with no request message yet → not a real request, excluded.
        AddConversation(db, bob.Id, me.Id, ConversationStatus.Pending, DateTime.UtcNow);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var page = await repo.GetPendingRequestsPageAsync(me.Id, 1, 20);

        Assert.Empty(page.Items);
        Assert.Equal(0, page.TotalCount);
    }

    [Fact]
    public async Task FindBetween_ReturnsMessageLessConversation_SoGetOrCreateReusesIt()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");
        // Opened but never messaged — must still be findable so StartOrGet reuses it (no duplicate).
        var conv = AddConversation(db, me.Id, alice.Id, ConversationStatus.Pending, DateTime.UtcNow);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var found = await repo.FindBetweenAsync(me.Id, alice.Id);

        Assert.NotNull(found);
        Assert.Equal(conv.Id, found!.Id);
        Assert.Null(found.LastMessageAt);   // confirms it's the message-less thread
    }

    [Fact]
    public async Task GetPendingRequestsPage_OnlyIncoming_ExcludesMyOwnOutgoingRequests()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var bob = AddUser(db, "Bob");     // Bob → Me  (incoming, should appear)
        var carol = AddUser(db, "Carol"); // Me → Carol (outgoing, should NOT appear)

        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var incoming = AddConversation(db, bob.Id, me.Id, ConversationStatus.Pending, t0);
        AddMessage(db, incoming.Id, bob.Id, "hey can we chat", t0);
        incoming.LastMessageAt = t0;

        var outgoing = AddConversation(db, me.Id, carol.Id, ConversationStatus.Pending, t0.AddMinutes(1));
        AddMessage(db, outgoing.Id, me.Id, "hello Carol", t0.AddMinutes(1));
        outgoing.LastMessageAt = t0.AddMinutes(1);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);
        var page = await repo.GetPendingRequestsPageAsync(me.Id, 1, 20);

        var row = Assert.Single(page.Items);
        Assert.Equal(incoming.Id, row.Id);
        Assert.True(row.IsRequest);   // pending, initiated by the other side
        Assert.Equal(bob.Id, row.OtherUser.UserId);
        Assert.Equal("hey can we chat", row.LastMessagePreview);
    }

    // ===== MESSAGES (keyset) =====

    [Fact]
    public async Task GetMessages_NewestFirst_RespectsLimitAndBeforeCursor()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");

        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var conv = AddConversation(db, me.Id, alice.Id, ConversationStatus.Accepted, t0);
        for (var i = 0; i < 5; i++)
            AddMessage(db, conv.Id, i % 2 == 0 ? me.Id : alice.Id, $"m{i}", t0.AddMinutes(i));
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);

        // Latest page (newest first): m4, m3
        var latest = await repo.GetMessagesAsync(conv.Id, me.Id, before: null, limit: 2);
        Assert.Equal(new[] { "m4", "m3" }, latest.Select(m => m.Body).ToArray());

        // Older page before m3's timestamp: m2, m1
        var older = await repo.GetMessagesAsync(conv.Id, me.Id, before: latest.Last().CreatedAt, limit: 2);
        Assert.Equal(new[] { "m2", "m1" }, older.Select(m => m.Body).ToArray());
    }

    // ===== SCALAR HELPERS =====

    [Fact]
    public async Task CountMessagesBySender_CountsOnlyThatSender()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");

        var t0 = DateTime.UtcNow.AddMinutes(-10);
        var conv = AddConversation(db, me.Id, alice.Id, ConversationStatus.Accepted, t0);
        AddMessage(db, conv.Id, me.Id, "a", t0.AddMinutes(1));
        AddMessage(db, conv.Id, me.Id, "b", t0.AddMinutes(2));
        AddMessage(db, conv.Id, alice.Id, "c", t0.AddMinutes(3));
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);

        Assert.Equal(2, await repo.CountMessagesBySenderAsync(conv.Id, me.Id));
        Assert.Equal(1, await repo.CountMessagesBySenderAsync(conv.Id, alice.Id));
    }

    [Fact]
    public async Task AreConnected_TrueForAcceptedEitherDirection_FalseOtherwise()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");
        var bob = AddUser(db, "Bob");

        db.Connections.Add(new Connection
        {
            Id = Guid.NewGuid(), RequesterId = alice.Id, ReceiverId = me.Id,
            Status = ConnectionStatus.Accepted, CreatedAt = DateTime.UtcNow
        });
        db.Connections.Add(new Connection
        {
            Id = Guid.NewGuid(), RequesterId = me.Id, ReceiverId = bob.Id,
            Status = ConnectionStatus.Pending, CreatedAt = DateTime.UtcNow
        });
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);

        Assert.True(await repo.AreConnectedAsync(me.Id, alice.Id));   // accepted (their direction)
        Assert.True(await repo.AreConnectedAsync(alice.Id, me.Id));   // symmetric
        Assert.False(await repo.AreConnectedAsync(me.Id, bob.Id));    // only pending
    }

    [Fact]
    public async Task FindBetween_ReturnsThread_RegardlessOfInitiator()
    {
        using var db = NewContext();
        var me = AddUser(db, "Me");
        var alice = AddUser(db, "Alice");

        var conv = AddConversation(db, alice.Id, me.Id, ConversationStatus.Accepted, DateTime.UtcNow);
        await db.SaveChangesAsync();

        var repo = new ConversationRepository(db);

        var found1 = await repo.FindBetweenAsync(me.Id, alice.Id);
        var found2 = await repo.FindBetweenAsync(alice.Id, me.Id);

        Assert.NotNull(found1);
        Assert.Equal(conv.Id, found1!.Id);
        Assert.Equal(conv.Id, found2!.Id);
    }
}
