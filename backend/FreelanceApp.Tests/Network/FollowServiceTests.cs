using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Connections.DTOs;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Application.Features.Network.Services;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Tests.Network;

public class FollowServiceTests
{
    private static readonly Guid Me = Guid.NewGuid();
    private static readonly Guid OtherA = Guid.NewGuid();
    private static readonly Guid OtherB = Guid.NewGuid();

    // ===== Helpers =====

    private static (FollowService sut, InMemoryFollowRepository repo) BuildFollowSut()
    {
        var repo = new InMemoryFollowRepository();
        var settings = Options.Create(new SuggestionSettings());
        var scorer = new WeightedFollowSuggestionScorer(settings);
        return (new FollowService(repo, scorer, settings, NullLogger<FollowService>.Instance), repo);
    }

    private static NetworkService BuildNetworkSut(
        InMemoryFollowRepository followRepo,
        InMemoryConnectionRepository? connRepo = null)
    {
        connRepo ??= new InMemoryConnectionRepository();
        return new NetworkService(connRepo, followRepo);
    }

    // ===== Tests =====

    [Fact]
    public async Task Follow_CreatesExactlyOneRow()
    {
        var (sut, repo) = BuildFollowSut();
        repo.SeedUser(OtherA);

        await sut.FollowAsync(Me, OtherA);

        Assert.Equal(1, repo.Count);
    }

    [Fact]
    public async Task FollowTwice_IsIdempotent_StillOneRow()
    {
        var (sut, repo) = BuildFollowSut();
        repo.SeedUser(OtherA);

        await sut.FollowAsync(Me, OtherA);
        var ex = await Record.ExceptionAsync(() => sut.FollowAsync(Me, OtherA));

        Assert.Null(ex);
        Assert.Equal(1, repo.Count);
    }

    [Fact]
    public async Task Unfollow_RemovesTheRow()
    {
        var (sut, repo) = BuildFollowSut();
        repo.SeedUser(OtherA);
        repo.SeedFollow(Me, OtherA);

        await sut.UnfollowAsync(Me, OtherA);

        Assert.Equal(0, repo.Count);
    }

    [Fact]
    public async Task Unfollow_WhenNotFollowing_IsIdempotent()
    {
        var (sut, repo) = BuildFollowSut();

        var ex = await Record.ExceptionAsync(() => sut.UnfollowAsync(Me, OtherA));

        Assert.Null(ex);
        Assert.Equal(0, repo.Count);
    }

    [Fact]
    public async Task FollowSelf_ThrowsValidationException()
    {
        var (sut, _) = BuildFollowSut();

        await Assert.ThrowsAsync<ValidationException>(() => sut.FollowAsync(Me, Me));
    }

    [Fact]
    public async Task FollowNonExistentUser_ThrowsNotFoundException()
    {
        var (sut, _) = BuildFollowSut();
        // OtherA is NOT seeded as a known user

        await Assert.ThrowsAsync<NotFoundException>(() => sut.FollowAsync(Me, OtherA));
    }

    [Fact]
    public async Task GetFollowers_ReturnsOnlyUsersWhoFollowMe()
    {
        var (sut, repo) = BuildFollowSut();
        // OtherA follows Me; Me follows OtherB (should NOT appear in followers)
        repo.SeedFollow(OtherA, Me);
        repo.SeedFollow(Me, OtherB);

        var result = await sut.GetFollowersAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.Equal(OtherA, row.UserId);
    }

    [Fact]
    public async Task GetFollowing_ReturnsOnlyUsersIFollow()
    {
        var (sut, repo) = BuildFollowSut();
        // Me follows OtherA; OtherB follows Me (should NOT appear in following)
        repo.SeedFollow(Me, OtherA);
        repo.SeedFollow(OtherB, Me);

        var result = await sut.GetFollowingAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.Equal(OtherA, row.UserId);
    }

    [Fact]
    public async Task IsFollowingBack_TrueOnlyForMutualFollow()
    {
        var (sut, repo) = BuildFollowSut();
        // OtherA follows Me AND I follow OtherA — mutual
        repo.SeedFollow(OtherA, Me);
        repo.SeedFollow(Me, OtherA);

        // OtherB follows Me but I do NOT follow OtherB — one-way
        repo.SeedFollow(OtherB, Me);

        var result = await sut.GetFollowersAsync(Me, 1, 10);

        Assert.Equal(2, result.Items.Count);
        var mutualRow = result.Items.Single(r => r.UserId == OtherA);
        var oneWayRow = result.Items.Single(r => r.UserId == OtherB);

        Assert.True(mutualRow.IsFollowingBack);
        Assert.False(oneWayRow.IsFollowingBack);
    }

    [Fact]
    public async Task Follow_IsIndependentOfConnection()
    {
        // Accepting a connection must NOT create a follow row.
        // Creating a follow must NOT create a connection row.
        var followRepo = new InMemoryFollowRepository();
        followRepo.SeedUser(OtherA);
        var connRepo = new InMemoryConnectionRepository();

        // Seed an accepted connection between Me and OtherA
        connRepo.Seed(new Connection
        {
            Id = Guid.NewGuid(), RequesterId = Me,
            ReceiverId = OtherA, Status = ConnectionStatus.Accepted
        });

        // Connection did NOT create a follow
        Assert.Equal(0, followRepo.Count);

        // Create a follow
        var (sut2, _) = BuildFollowSut();
        // Replace the repo with the one that has OtherA seeded
        var settings2 = Options.Create(new SuggestionSettings());
        var followSut = new FollowService(followRepo, new WeightedFollowSuggestionScorer(settings2), settings2, NullLogger<FollowService>.Instance);
        await followSut.FollowAsync(Me, OtherA);
        Assert.Equal(1, followRepo.Count);

        // Follow did NOT create a connection (connection count is still the 1 we seeded)
        Assert.Equal(1, connRepo.Count);
    }

    [Fact]
    public async Task Overview_FollowCountsAreCorrectAndAsymmetric()
    {
        // I follow 2 people, 5 people follow me
        var followRepo = new InMemoryFollowRepository();
        followRepo.SeedFollow(Me, OtherA);
        followRepo.SeedFollow(Me, OtherB);
        followRepo.SeedFollow(Guid.NewGuid(), Me);
        followRepo.SeedFollow(Guid.NewGuid(), Me);
        followRepo.SeedFollow(Guid.NewGuid(), Me);
        followRepo.SeedFollow(Guid.NewGuid(), Me);
        followRepo.SeedFollow(Guid.NewGuid(), Me);

        var sut = BuildNetworkSut(followRepo);
        var result = await sut.GetOverviewAsync(Me, CancellationToken.None);

        Assert.Equal(2, result.FollowingCount);
        Assert.Equal(5, result.FollowersCount);
    }

    [Fact]
    public async Task Overview_ZeroFollows_ReturnsBothZero()
    {
        // No follow rows at all — exercises the null-fallback path in GetFollowCountsAsync
        var followRepo = new InMemoryFollowRepository();
        var sut = BuildNetworkSut(followRepo);

        var result = await sut.GetOverviewAsync(Me, CancellationToken.None);

        Assert.Equal(0, result.FollowingCount);
        Assert.Equal(0, result.FollowersCount);
    }

    [Fact]
    public async Task Overview_ExistingConnectionFields_Unchanged()
    {
        // Regression guard: adding follow counts must not break existing connection counts.
        var followRepo = new InMemoryFollowRepository();
        followRepo.SeedFollow(Me, OtherA);

        var connRepo = new InMemoryConnectionRepository();
        connRepo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = Me, ReceiverId = OtherA, Status = ConnectionStatus.Accepted });
        connRepo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = Me, ReceiverId = OtherB, Status = ConnectionStatus.Pending });
        connRepo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = OtherB, ReceiverId = Me, Status = ConnectionStatus.Pending });

        var sut = BuildNetworkSut(followRepo, connRepo);
        var result = await sut.GetOverviewAsync(Me, CancellationToken.None);

        Assert.Equal(1, result.ConnectionsCount);
        Assert.Equal(1, result.InvitesSentCount);
        Assert.Equal(1, result.InvitesReceivedCount);
    }

    [Fact]
    public async Task GetFollowers_Pagination_PageSizeClampedAndPage2ReturnsNextSlice()
    {
        var (sut, repo) = BuildFollowSut();

        for (var i = 0; i < 60; i++)
            repo.SeedFollowWithTime(Guid.NewGuid(), Me, DateTime.UtcNow.AddMinutes(-i));

        // pageSize 1000 should clamp to 50
        var page1 = await sut.GetFollowersAsync(Me, 1, 1000);
        Assert.Equal(FollowService.MaxPageSize, page1.Items.Count);
        Assert.Equal(FollowService.MaxPageSize, page1.PageSize);
        Assert.Equal(60, page1.TotalCount);

        var page2 = await sut.GetFollowersAsync(Me, 2, FollowService.MaxPageSize);
        Assert.Equal(10, page2.Items.Count);
        Assert.Equal(60, page2.TotalCount);

        var page1Ids = page1.Items.Select(x => x.UserId).ToHashSet();
        Assert.All(page2.Items, item => Assert.DoesNotContain(item.UserId, page1Ids));
    }

    // ===== Fakes =====

    private sealed class InMemoryFollowRepository : IFollowRepository
    {
        private readonly List<Follow> _follows = [];
        private readonly HashSet<Guid> _knownUsers = [];

        public int Count => _follows.Count;

        public void SeedUser(Guid userId) => _knownUsers.Add(userId);

        public void SeedFollow(Guid followerId, Guid followeeId) =>
            _follows.Add(new Follow
            {
                Id = Guid.NewGuid(), FollowerId = followerId,
                FolloweeId = followeeId, CreatedAt = DateTime.UtcNow.AddTicks(-(_follows.Count * 1000L))
            });

        public void SeedFollowWithTime(Guid followerId, Guid followeeId, DateTime createdAt) =>
            _follows.Add(new Follow
            {
                Id = Guid.NewGuid(), FollowerId = followerId,
                FolloweeId = followeeId, CreatedAt = createdAt
            });

        public Task FollowAsync(Guid followerId, Guid followeeId, CancellationToken ct)
        {
            if (!_follows.Any(f => f.FollowerId == followerId && f.FolloweeId == followeeId))
                _follows.Add(new Follow
                {
                    Id = Guid.NewGuid(), FollowerId = followerId,
                    FolloweeId = followeeId, CreatedAt = DateTime.UtcNow
                });
            return Task.CompletedTask;
        }

        public Task UnfollowAsync(Guid followerId, Guid followeeId, CancellationToken ct)
        {
            _follows.RemoveAll(f => f.FollowerId == followerId && f.FolloweeId == followeeId);
            return Task.CompletedTask;
        }

        public Task<bool> UserExistsAsync(Guid userId, CancellationToken ct) =>
            Task.FromResult(_knownUsers.Contains(userId));

        public Task<PagedResult<FollowUserResponse>> GetFollowersAsync(
            Guid meId, int page, int pageSize, CancellationToken ct)
        {
            var all = _follows
                .Where(f => f.FolloweeId == meId)
                .OrderByDescending(f => f.CreatedAt)
                .Select(f => new FollowUserResponse
                {
                    UserId = f.FollowerId,
                    FullName = "Test",
                    IsFollowingBack = _follows.Any(fb => fb.FollowerId == meId && fb.FolloweeId == f.FollowerId)
                })
                .ToList();

            var total = all.Count;
            var items = all.Skip((page - 1) * pageSize).Take(pageSize).ToList();
            return Task.FromResult(new PagedResult<FollowUserResponse>
            {
                Items = items, Page = page, PageSize = pageSize, TotalCount = total
            });
        }

        public Task<PagedResult<FollowUserResponse>> GetFollowingAsync(
            Guid meId, int page, int pageSize, CancellationToken ct)
        {
            var all = _follows
                .Where(f => f.FollowerId == meId)
                .OrderByDescending(f => f.CreatedAt)
                .Select(f => new FollowUserResponse
                {
                    UserId = f.FolloweeId,
                    FullName = "Test",
                    IsFollowingBack = _follows.Any(fb => fb.FollowerId == f.FolloweeId && fb.FolloweeId == meId)
                })
                .ToList();

            var total = all.Count;
            var items = all.Skip((page - 1) * pageSize).Take(pageSize).ToList();
            return Task.FromResult(new PagedResult<FollowUserResponse>
            {
                Items = items, Page = page, PageSize = pageSize, TotalCount = total
            });
        }

        public Task<(bool IsFollowing, bool IsFollowedBy)> GetFollowStatusAsync(
            Guid meId, Guid targetId, CancellationToken ct)
        {
            var isFollowing = _follows.Any(f => f.FollowerId == meId && f.FolloweeId == targetId);
            var isFollowedBy = _follows.Any(f => f.FollowerId == targetId && f.FolloweeId == meId);
            return Task.FromResult((isFollowing, isFollowedBy));
        }

        public Task<(int Following, int Followers)> GetFollowCountsAsync(Guid meId, CancellationToken ct)
        {
            var following = _follows.Count(f => f.FollowerId == meId);
            var followers = _follows.Count(f => f.FolloweeId == meId);
            return Task.FromResult((following, followers));
        }

        // Suggestion-specific stubs — not exercised by the existing follow tests.
        public Task<List<Guid>> GetMyAcceptedConnectionIdsAsync(Guid meId, CancellationToken ct) =>
            Task.FromResult(new List<Guid>());
        public Task<List<string>> GetMySkillsAsync(Guid meId, CancellationToken ct) =>
            Task.FromResult(new List<string>());
        public Task<List<Guid>> GetFollowSuggestionCandidateIdsAsync(
            Guid meId, IReadOnlyList<Guid> myConnectionIds, string[] mySkillsLower,
            int topPopularCount, CancellationToken ct) =>
            Task.FromResult(new List<Guid>());
        public Task<List<(User User, Profile? Profile)>> LoadFollowSuggestionDetailsAsync(
            IReadOnlyList<Guid> candidateIds, CancellationToken ct) =>
            Task.FromResult(new List<(User, Profile?)>());
        public Task<Dictionary<Guid, int>> GetFollowerCountsForCandidatesAsync(
            IReadOnlyList<Guid> candidateIds, CancellationToken ct) =>
            Task.FromResult(new Dictionary<Guid, int>());
        public Task<Dictionary<Guid, SocialReachData>> GetSocialReachDataAsync(
            IReadOnlyList<Guid> candidateIds, IReadOnlyList<Guid> myConnectionIds, CancellationToken ct) =>
            Task.FromResult(new Dictionary<Guid, SocialReachData>());
        public Task DismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct) =>
            Task.CompletedTask;
        public Task UndismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct) =>
            Task.CompletedTask;
    }

    private sealed class InMemoryConnectionRepository : IConnectionRepository
    {
        private readonly List<Connection> _data = [];

        public int Count => _data.Count;
        public void Seed(Connection c) => _data.Add(c);

        public Task<(int Connections, int InvitesSent, int InvitesReceived)> GetCountsAsync(
            Guid userId, CancellationToken ct)
        {
            var conns = _data.Count(c =>
                c.Status == ConnectionStatus.Accepted &&
                (c.RequesterId == userId || c.ReceiverId == userId));
            var sent = _data.Count(c =>
                c.Status == ConnectionStatus.Pending && c.RequesterId == userId);
            var received = _data.Count(c =>
                c.Status == ConnectionStatus.Pending && c.ReceiverId == userId);
            return Task.FromResult((conns, sent, received));
        }

        public Task<Connection?> GetByIdAsync(Guid id) => Task.FromResult<Connection?>(null);
        public Task<List<Connection>> GetBetweenUsersAsync(Guid a, Guid b) => Task.FromResult(new List<Connection>());
        public Task AddAsync(Connection c) { _data.Add(c); return Task.CompletedTask; }
        public void Remove(Connection c) => _data.Remove(c);
        public Task<List<ConnectionUserDto>> GetAcceptedUsersAsync(Guid userId) => Task.FromResult(new List<ConnectionUserDto>());
        public Task<PagedResult<PendingRequestDto>> GetPendingIncomingWithMutualsAsync(Guid meId, int page, int pageSize, CancellationToken ct) => Task.FromResult(new PagedResult<PendingRequestDto>());
        public Task<PagedResult<PendingRequestDto>> GetPendingOutgoingAsync(Guid userId, int page, int pageSize, CancellationToken ct) => Task.FromResult(new PagedResult<PendingRequestDto>());
        public Task<ConnectionInvitePolicy?> GetReceiverPolicyAsync(Guid receiverId, CancellationToken ct) => Task.FromResult<ConnectionInvitePolicy?>(null);
        public Task<bool> ShareMutualConnectionAsync(Guid userA, Guid userB, CancellationToken ct) => Task.FromResult(false);
        public Task SaveChangesAsync() => Task.CompletedTask;
    }
}
