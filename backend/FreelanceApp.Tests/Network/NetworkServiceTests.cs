using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Connections.DTOs;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Application.Features.Network.Services;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Tests.Network;

public class NetworkServiceTests
{
    private static readonly Guid Me = Guid.NewGuid();
    private static readonly Guid OtherA = Guid.NewGuid();
    private static readonly Guid OtherB = Guid.NewGuid();

    private static (NetworkService sut, InMemoryConnectionRepository repo) BuildSut()
    {
        var connRepo = new InMemoryConnectionRepository();
        var followRepo = new NoOpFollowRepository();
        return (new NetworkService(connRepo, followRepo), connRepo);
    }

    [Fact]
    public async Task GetOverview_NewUser_AllCountsAreZero()
    {
        var (sut, _) = BuildSut();

        var result = await sut.GetOverviewAsync(Me, CancellationToken.None);

        Assert.Equal(0, result.ConnectionsCount);
        Assert.Equal(0, result.InvitesSentCount);
        Assert.Equal(0, result.InvitesReceivedCount);
    }

    [Fact]
    public async Task GetOverview_AcceptedCountedBothDirections()
    {
        var (sut, repo) = BuildSut();
        // Me as requester
        repo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = Me, ReceiverId = OtherA, Status = ConnectionStatus.Accepted });
        // Me as receiver
        repo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = OtherB, ReceiverId = Me, Status = ConnectionStatus.Accepted });

        var result = await sut.GetOverviewAsync(Me, CancellationToken.None);

        Assert.Equal(2, result.ConnectionsCount);
        Assert.Equal(0, result.InvitesSentCount);
        Assert.Equal(0, result.InvitesReceivedCount);
    }

    [Fact]
    public async Task GetOverview_PendingAsRequester_OnlyInvitesSentIncremented()
    {
        var (sut, repo) = BuildSut();
        repo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = Me, ReceiverId = OtherA, Status = ConnectionStatus.Pending });

        var result = await sut.GetOverviewAsync(Me, CancellationToken.None);

        Assert.Equal(0, result.ConnectionsCount);
        Assert.Equal(1, result.InvitesSentCount);
        Assert.Equal(0, result.InvitesReceivedCount);
    }

    [Fact]
    public async Task GetOverview_PendingAsReceiver_OnlyInvitesReceivedIncremented()
    {
        var (sut, repo) = BuildSut();
        repo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = OtherA, ReceiverId = Me, Status = ConnectionStatus.Pending });

        var result = await sut.GetOverviewAsync(Me, CancellationToken.None);

        Assert.Equal(0, result.ConnectionsCount);
        Assert.Equal(0, result.InvitesSentCount);
        Assert.Equal(1, result.InvitesReceivedCount);
    }

    [Fact]
    public async Task GetOverview_RejectedRows_ExcludedFromAllCounts()
    {
        var (sut, repo) = BuildSut();
        repo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = Me, ReceiverId = OtherA, Status = ConnectionStatus.Rejected });
        repo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = OtherA, ReceiverId = Me, Status = ConnectionStatus.Rejected });

        var result = await sut.GetOverviewAsync(Me, CancellationToken.None);

        Assert.Equal(0, result.ConnectionsCount);
        Assert.Equal(0, result.InvitesSentCount);
        Assert.Equal(0, result.InvitesReceivedCount);
    }

    [Fact]
    public async Task GetOverview_ConnectionsBetweenOtherUsers_NotCounted()
    {
        var (sut, repo) = BuildSut();
        repo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = OtherA, ReceiverId = OtherB, Status = ConnectionStatus.Accepted });
        repo.Seed(new Connection { Id = Guid.NewGuid(), RequesterId = OtherB, ReceiverId = OtherA, Status = ConnectionStatus.Pending });

        var result = await sut.GetOverviewAsync(Me, CancellationToken.None);

        Assert.Equal(0, result.ConnectionsCount);
        Assert.Equal(0, result.InvitesSentCount);
        Assert.Equal(0, result.InvitesReceivedCount);
    }

    // ===== Test double =====

    private sealed class InMemoryConnectionRepository : IConnectionRepository
    {
        private readonly List<Connection> _data = [];

        public void Seed(Connection connection) => _data.Add(connection);

        public Task<(int Connections, int InvitesSent, int InvitesReceived)> GetCountsAsync(
            Guid userId, CancellationToken ct)
        {
            var connections = _data.Count(c =>
                c.Status == ConnectionStatus.Accepted &&
                (c.RequesterId == userId || c.ReceiverId == userId));

            var invitesSent = _data.Count(c =>
                c.Status == ConnectionStatus.Pending && c.RequesterId == userId);

            var invitesReceived = _data.Count(c =>
                c.Status == ConnectionStatus.Pending && c.ReceiverId == userId);

            return Task.FromResult((connections, invitesSent, invitesReceived));
        }

        // Stubs — not exercised by network tests
        public Task<Connection?> GetByIdAsync(Guid id) => Task.FromResult<Connection?>(null);
        public Task<List<Connection>> GetBetweenUsersAsync(Guid a, Guid b) => Task.FromResult(new List<Connection>());
        public Task AddAsync(Connection connection) { _data.Add(connection); return Task.CompletedTask; }
        public void Remove(Connection connection) => _data.Remove(connection);
        public Task<List<ConnectionUserDto>> GetAcceptedUsersAsync(Guid userId) => Task.FromResult(new List<ConnectionUserDto>());
        public Task<PagedResult<PendingRequestDto>> GetPendingIncomingWithMutualsAsync(Guid meId, int page, int pageSize, CancellationToken ct) => Task.FromResult(new PagedResult<PendingRequestDto>());
        public Task<PagedResult<PendingRequestDto>> GetPendingOutgoingAsync(Guid userId, int page, int pageSize, CancellationToken ct) => Task.FromResult(new PagedResult<PendingRequestDto>());
        public Task<ConnectionInvitePolicy?> GetReceiverPolicyAsync(Guid receiverId, CancellationToken ct) => Task.FromResult<ConnectionInvitePolicy?>(null);
        public Task<bool> ShareMutualConnectionAsync(Guid userA, Guid userB, CancellationToken ct) => Task.FromResult(false);
        public Task SaveChangesAsync() => Task.CompletedTask;
    }

    private sealed class NoOpFollowRepository : IFollowRepository
    {
        public Task FollowAsync(Guid followerId, Guid followeeId, CancellationToken ct) => Task.CompletedTask;
        public Task UnfollowAsync(Guid followerId, Guid followeeId, CancellationToken ct) => Task.CompletedTask;
        public Task<bool> UserExistsAsync(Guid userId, CancellationToken ct) => Task.FromResult(false);
        public Task<PagedResult<FollowUserResponse>> GetFollowersAsync(Guid meId, int page, int pageSize, CancellationToken ct)
            => Task.FromResult(new PagedResult<FollowUserResponse>());
        public Task<PagedResult<FollowUserResponse>> GetFollowingAsync(Guid meId, int page, int pageSize, CancellationToken ct)
            => Task.FromResult(new PagedResult<FollowUserResponse>());
        public Task<(bool IsFollowing, bool IsFollowedBy)> GetFollowStatusAsync(Guid meId, Guid targetId, CancellationToken ct)
            => Task.FromResult((false, false));
        public Task<(int Following, int Followers)> GetFollowCountsAsync(Guid meId, CancellationToken ct)
            => Task.FromResult((0, 0));

        // Suggestion stubs — not exercised by network-overview tests.
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
}
