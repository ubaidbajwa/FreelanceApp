using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using FreelanceApp.Infrastructure.Repositories;
using Microsoft.EntityFrameworkCore;

namespace FreelanceApp.Tests.People;

public class PeopleRepositoryTests
{
    private static readonly Guid Me = Guid.NewGuid();

    // Fresh InMemory context per test — repo query LINQ-to-objects par chalti hai,
    // to LEFT JOIN + status subqueries + search + paging sab yahan faithfully test hote hain.
    private static AppDbContext NewContext() =>
        new(new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);

    private static User AddUser(AppDbContext db, string name, string? headline = null, bool profile = true)
    {
        var user = new User { Id = Guid.NewGuid(), Email = $"{Guid.NewGuid():N}@x.com", FullName = name };
        db.Users.Add(user);
        if (profile)
        {
            db.Profiles.Add(new Profile
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                DisplayName = name,
                Headline = headline,
                ProfilePhotoUrl = $"https://cdn/{user.Id}.jpg"
            });
        }
        return user;
    }

    private static void Connect(AppDbContext db, Guid requester, Guid receiver, ConnectionStatus status)
    {
        db.Connections.Add(new Connection
        {
            Id = Guid.NewGuid(),
            RequesterId = requester,
            ReceiverId = receiver,
            Status = status,
            CreatedAt = DateTime.UtcNow,
            RespondedAt = status == ConnectionStatus.Pending ? null : DateTime.UtcNow
        });
    }

    // ===== SEARCH =====

    [Fact]
    public async Task Search_MatchesByName_CaseInsensitive()
    {
        using var db = NewContext();
        AddUser(db, "Alice Johnson");
        AddUser(db, "Bob Smith");
        await db.SaveChangesAsync();

        var repo = new PeopleRepository(db);
        var result = await repo.SearchAsync(Me, "alice", 1, 20);

        Assert.Equal(1, result.TotalCount);
        Assert.Equal("Alice Johnson", result.Items[0].FullName);
    }

    [Fact]
    public async Task Search_MatchesByHeadline_CaseInsensitive()
    {
        using var db = NewContext();
        AddUser(db, "Alice Johnson", headline: "Senior Flutter Engineer");
        AddUser(db, "Bob Smith", headline: "Backend Developer");
        await db.SaveChangesAsync();

        var repo = new PeopleRepository(db);
        var result = await repo.SearchAsync(Me, "FLUTTER", 1, 20);

        Assert.Equal(1, result.TotalCount);
        Assert.Equal("Alice Johnson", result.Items[0].FullName);
    }

    [Fact]
    public async Task Search_EmptyTerm_ReturnsEveryoneExceptSelf()
    {
        using var db = NewContext();
        db.Users.Add(new User { Id = Me, Email = "me@x.com", FullName = "Me Myself" });
        AddUser(db, "Alice Johnson");
        AddUser(db, "Bob Smith");
        await db.SaveChangesAsync();

        var repo = new PeopleRepository(db);
        var result = await repo.SearchAsync(Me, null, 1, 20);

        Assert.Equal(2, result.TotalCount);
        Assert.DoesNotContain(result.Items, p => p.UserId == Me);
    }

    [Fact]
    public async Task Search_ExcludesCurrentUser_EvenWhenMatchingTerm()
    {
        using var db = NewContext();
        db.Users.Add(new User { Id = Me, Email = "me@x.com", FullName = "Alice Me" });
        AddUser(db, "Alice Johnson");
        await db.SaveChangesAsync();

        var repo = new PeopleRepository(db);
        var result = await repo.SearchAsync(Me, "alice", 1, 20);

        Assert.Equal(1, result.TotalCount);
        Assert.Equal("Alice Johnson", result.Items[0].FullName);
    }

    [Fact]
    public async Task Search_UserWithoutProfile_HasNullHeadlineAndPhoto()
    {
        using var db = NewContext();
        AddUser(db, "No Profile", profile: false);
        await db.SaveChangesAsync();

        var repo = new PeopleRepository(db);
        var result = await repo.SearchAsync(Me, null, 1, 20);

        Assert.Single(result.Items);
        Assert.Null(result.Items[0].Headline);
        Assert.Null(result.Items[0].PhotoUrl);
    }

    // ===== CONNECTION STATUS =====

    [Fact]
    public async Task Search_ProjectsCorrectConnectionStatus_PerState()
    {
        using var db = NewContext();
        var none = AddUser(db, "A None");
        var outgoing = AddUser(db, "B Outgoing");
        var incoming = AddUser(db, "C Incoming");
        var connected = AddUser(db, "D Connected");

        Connect(db, Me, outgoing.Id, ConnectionStatus.Pending);       // I requested them
        Connect(db, incoming.Id, Me, ConnectionStatus.Pending);       // they requested me
        Connect(db, connected.Id, Me, ConnectionStatus.Accepted);     // accepted (their direction)
        await db.SaveChangesAsync();

        var repo = new PeopleRepository(db);
        var result = await repo.SearchAsync(Me, null, 1, 20);
        var byId = result.Items.ToDictionary(p => p.UserId, p => p.ConnectionStatus);

        Assert.Equal("None", byId[none.Id]);
        Assert.Equal("PendingOutgoing", byId[outgoing.Id]);
        Assert.Equal("PendingIncoming", byId[incoming.Id]);
        Assert.Equal("Connected", byId[connected.Id]);
    }

    [Fact]
    public async Task Search_RejectedConnection_ShowsAsNone()
    {
        using var db = NewContext();
        var other = AddUser(db, "Rejected Person");
        Connect(db, Me, other.Id, ConnectionStatus.Rejected);
        await db.SaveChangesAsync();

        var repo = new PeopleRepository(db);
        var result = await repo.SearchAsync(Me, null, 1, 20);

        Assert.Equal("None", result.Items.Single().ConnectionStatus);
    }

    // ===== PAGINATION =====

    [Fact]
    public async Task Search_Paginates_WithCorrectSlicesAndTotalCount()
    {
        using var db = NewContext();
        // 25 users: "User 01".."User 25" — name asc order predictable
        for (int i = 1; i <= 25; i++)
            AddUser(db, $"User {i:D2}");
        await db.SaveChangesAsync();

        var repo = new PeopleRepository(db);

        var page1 = await repo.SearchAsync(Me, null, 1, 10);
        Assert.Equal(25, page1.TotalCount);
        Assert.Equal(10, page1.Items.Count);
        Assert.Equal("User 01", page1.Items.First().FullName);
        Assert.Equal("User 10", page1.Items.Last().FullName);
        Assert.True(page1.HasNextPage);

        var page3 = await repo.SearchAsync(Me, null, 3, 10);
        Assert.Equal(5, page3.Items.Count);              // remainder
        Assert.Equal("User 21", page3.Items.First().FullName);
        Assert.Equal("User 25", page3.Items.Last().FullName);
        Assert.False(page3.HasNextPage);
    }

    [Fact]
    public async Task Search_OrdersByNameThenId_Stable()
    {
        using var db = NewContext();
        AddUser(db, "Zed");
        AddUser(db, "Amy");
        AddUser(db, "Mia");
        await db.SaveChangesAsync();

        var repo = new PeopleRepository(db);
        var result = await repo.SearchAsync(Me, null, 1, 20);

        Assert.Equal(new[] { "Amy", "Mia", "Zed" }, result.Items.Select(p => p.FullName).ToArray());
    }
}
