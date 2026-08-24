using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Application.Features.Network.Services;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Services;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Tests.Network;

public class SuggestionServiceTests
{
    private static readonly Guid Me = Guid.NewGuid();

    // ===== TEST FACTORY =====

    private static SuggestionService BuildSut(
        InMemorySuggestionRepository repo,
        SuggestionSettings? settings = null,
        ISuggestionScorer? scorer = null,
        ISuggestionCache? cache = null)
    {
        settings ??= new SuggestionSettings();
        scorer ??= new WeightedSuggestionScorer(Options.Create(settings));
        cache ??= new NoOpSuggestionCache();
        return new SuggestionService(repo, scorer, cache, Options.Create(settings));
    }

    // ===== SCORING =====

    [Fact]
    public async Task Score_TwoMutuals_OneSharedSkill_Is25()
    {
        var repo = new InMemorySuggestionRepository();
        var mutual1 = Guid.NewGuid();
        var mutual2 = Guid.NewGuid();
        var candidate = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);
        repo.SeedUser(candidate);
        repo.SeedProfile(candidate.Id, ["React", "TypeScript"]);

        repo.SeedConnection(Me, mutual1, ConnectionStatus.Accepted);
        repo.SeedConnection(Me, mutual2, ConnectionStatus.Accepted);
        repo.SeedConnection(candidate.Id, mutual1, ConnectionStatus.Accepted);
        repo.SeedConnection(candidate.Id, mutual2, ConnectionStatus.Accepted);

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.Equal(candidate.Id, row.UserId);
        Assert.Equal(25, row.Score);
        Assert.Equal(2, row.MutualConnectionsCount);
        Assert.Single(row.SharedSkills);
        Assert.Equal("React", row.SharedSkills[0]);
    }

    [Fact]
    public async Task SharedSkills_AreCaseInsensitive()
    {
        var repo = new InMemorySuggestionRepository();
        var candidate = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["Flutter"]);
        repo.SeedUser(candidate);
        repo.SeedProfile(candidate.Id, ["flutter"]);

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.Single(row.SharedSkills);
        Assert.Equal(5, row.Score);
    }

    [Fact]
    public async Task ZeroSignalCandidate_NotReturned()
    {
        var repo = new InMemorySuggestionRepository();
        var candidate = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);
        repo.SeedUser(candidate);
        repo.SeedProfile(candidate.Id, ["TypeScript"]);  // no overlap, no mutuals

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        Assert.Empty(result.Items);
    }

    // ===== EXCLUSIONS =====

    [Fact]
    public async Task AcceptedConnection_Excluded()
    {
        var repo = new InMemorySuggestionRepository();
        var other = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);
        repo.SeedUser(other);
        repo.SeedProfile(other.Id, ["React"]);
        repo.SeedConnection(Me, other.Id, ConnectionStatus.Accepted);

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        Assert.Empty(result.Items);
    }

    [Fact]
    public async Task PendingConnection_EitherDirection_Excluded()
    {
        var repo = new InMemorySuggestionRepository();
        var userB = MakeUser();
        var userC = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);

        repo.SeedUser(userB);
        repo.SeedProfile(userB.Id, ["React"]);
        repo.SeedConnection(Me, userB.Id, ConnectionStatus.Pending);

        repo.SeedUser(userC);
        repo.SeedProfile(userC.Id, ["React"]);
        repo.SeedConnection(userC.Id, Me, ConnectionStatus.Pending);

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        Assert.Empty(result.Items);
    }

    [Fact]
    public async Task DismissedUser_Excluded()
    {
        var repo = new InMemorySuggestionRepository();
        var dismissed = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);
        repo.SeedUser(dismissed);
        repo.SeedProfile(dismissed.Id, ["React"]);

        var sut = BuildSut(repo);
        await sut.DismissAsync(Me, dismissed.Id);

        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        Assert.Empty(result.Items);
    }

    [Fact]
    public async Task Self_Excluded()
    {
        var repo = new InMemorySuggestionRepository();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        Assert.Empty(result.Items);
    }

    // ===== ORDERING =====

    [Fact]
    public async Task HigherScore_RanksFirst_CreatedAt_BreaksTies()
    {
        var repo = new InMemorySuggestionRepository();
        var mutual = Guid.NewGuid();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React", "Flutter"]);
        repo.SeedConnection(Me, mutual, ConnectionStatus.Accepted);

        var userA = MakeUser(createdAt: DateTime.UtcNow.AddMinutes(-5));
        repo.SeedUser(userA);
        repo.SeedProfile(userA.Id, ["React", "Flutter"]);
        repo.SeedConnection(userA.Id, mutual, ConnectionStatus.Accepted);

        var userB = MakeUser(createdAt: DateTime.UtcNow.AddMinutes(-3));
        repo.SeedUser(userB);
        repo.SeedProfile(userB.Id, ["React"]);

        var userC = MakeUser(createdAt: DateTime.UtcNow.AddMinutes(-10));
        var userD = MakeUser(createdAt: DateTime.UtcNow.AddMinutes(-1));
        repo.SeedUser(userC);
        repo.SeedProfile(userC.Id, ["Flutter"]);
        repo.SeedUser(userD);
        repo.SeedProfile(userD.Id, ["React"]);

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        Assert.Equal(4, result.Items.Count);
        Assert.Equal(userA.Id, result.Items[0].UserId);   // score 20
        Assert.Equal(20, result.Items[0].Score);
        Assert.Equal(userD.Id, result.Items[1].UserId);   // score 5, newest
        Assert.Equal(userB.Id, result.Items[2].UserId);   // score 5
        Assert.Equal(userC.Id, result.Items[3].UserId);   // score 5, oldest
    }

    // ===== PAGINATION =====

    [Fact]
    public async Task Pagination_PageSizeClampedTo50_Page2ReturnsNextSlice()
    {
        var repo = new InMemorySuggestionRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);

        for (var i = 0; i < 60; i++)
        {
            var u = MakeUser(createdAt: DateTime.UtcNow.AddMinutes(-i));
            repo.SeedUser(u);
            repo.SeedProfile(u.Id, ["React"]);
        }

        var sut = BuildSut(repo);

        var page1 = await sut.GetSuggestionsAsync(Me, 1, 1000);
        Assert.Equal(SuggestionService.MaxPageSize, page1.Items.Count);
        Assert.Equal(SuggestionService.MaxPageSize, page1.PageSize);
        Assert.Equal(60, page1.TotalCount);

        var page2 = await sut.GetSuggestionsAsync(Me, 2, SuggestionService.MaxPageSize);
        Assert.Equal(10, page2.Items.Count);
        Assert.Equal(60, page2.TotalCount);

        var page1Ids = page1.Items.Select(x => x.UserId).ToHashSet();
        Assert.All(page2.Items, item => Assert.DoesNotContain(item.UserId, page1Ids));
    }

    // ===== DISMISS =====

    [Fact]
    public async Task DismissTwice_IsIdempotent()
    {
        var repo = new InMemorySuggestionRepository();
        var sut = BuildSut(repo);
        var targetId = Guid.NewGuid();

        await sut.DismissAsync(Me, targetId);
        var ex = await Record.ExceptionAsync(() => sut.DismissAsync(Me, targetId));

        Assert.Null(ex);
    }

    [Fact]
    public async Task DismissSelf_Throws400()
    {
        var repo = new InMemorySuggestionRepository();
        var sut = BuildSut(repo);

        await Assert.ThrowsAsync<ValidationException>(() => sut.DismissAsync(Me, Me));
    }

    // ===== UNDISMISS (N5) =====

    [Fact]
    public async Task DismissThenUndismiss_UserReappearsInSuggestions()
    {
        var repo = new InMemorySuggestionRepository();
        var candidate = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);
        repo.SeedUser(candidate);
        repo.SeedProfile(candidate.Id, ["React"]);

        var sut = BuildSut(repo);
        await sut.DismissAsync(Me, candidate.Id);

        var afterDismiss = await sut.GetSuggestionsAsync(Me, 1, 10);
        Assert.Empty(afterDismiss.Items);

        await sut.UndismissAsync(Me, candidate.Id);

        var afterUndismiss = await sut.GetSuggestionsAsync(Me, 1, 10);
        Assert.Single(afterUndismiss.Items);
        Assert.Equal(candidate.Id, afterUndismiss.Items[0].UserId);
    }

    [Fact]
    public async Task UndismissWhenNeverDismissed_NoException()
    {
        var repo = new InMemorySuggestionRepository();
        var sut = BuildSut(repo);

        var ex = await Record.ExceptionAsync(() => sut.UndismissAsync(Me, Guid.NewGuid()));

        Assert.Null(ex);
    }

    [Fact]
    public async Task UndismissTwice_IsIdempotent()
    {
        var repo = new InMemorySuggestionRepository();
        var sut = BuildSut(repo);
        var targetId = Guid.NewGuid();

        await sut.DismissAsync(Me, targetId);
        await sut.UndismissAsync(Me, targetId);
        var ex = await Record.ExceptionAsync(() => sut.UndismissAsync(Me, targetId));

        Assert.Null(ex);
    }

    [Fact]
    public async Task UndismissX_DoesNotAffectDismissalOfY()
    {
        var repo = new InMemorySuggestionRepository();
        var userX = MakeUser();
        var userY = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);
        repo.SeedUser(userX);
        repo.SeedProfile(userX.Id, ["React"]);
        repo.SeedUser(userY);
        repo.SeedProfile(userY.Id, ["React"]);

        var sut = BuildSut(repo);
        await sut.DismissAsync(Me, userX.Id);
        await sut.DismissAsync(Me, userY.Id);
        await sut.UndismissAsync(Me, userX.Id);

        var result = await sut.GetSuggestionsAsync(Me, 1, 10);
        Assert.Single(result.Items);
        Assert.Equal(userX.Id, result.Items[0].UserId);
    }

    // ===== SIGNAL-DRIVEN CANDIDATE SELECTION (new tests 12-19) =====

    [Fact]
    public async Task FriendOfFriend_FoundEvenWhenOldestUser()
    {
        // Regression guard: the old ORDER BY CreatedAt DESC LIMIT n implementation would miss
        // highly-relevant older users if the pool exceeded the cap with newer users.
        // Signal-driven selection finds FOF candidates regardless of CreatedAt.
        var repo = new InMemorySuggestionRepository();
        var friend = Guid.NewGuid();
        var oldFof = MakeUser(createdAt: new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc));

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, []);
        repo.SeedUser(oldFof);
        repo.SeedProfile(oldFof.Id, []);
        repo.SeedConnection(Me, friend, ConnectionStatus.Accepted);
        repo.SeedConnection(oldFof.Id, friend, ConnectionStatus.Accepted);

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.Equal(oldFof.Id, row.UserId);
        Assert.Equal(10, row.Score);  // 1 mutual × 10
    }

    [Fact]
    public async Task SkillOnlyCandidate_ZeroMutuals_IsFound()
    {
        var repo = new InMemorySuggestionRepository();
        var candidate = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["TypeScript"]);
        repo.SeedUser(candidate);
        repo.SeedProfile(candidate.Id, ["TypeScript"]);

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.Equal(0, row.MutualConnectionsCount);
        Assert.Equal(5, row.Score);
    }

    [Fact]
    public async Task NoSignalUser_NotInCandidatePool()
    {
        // User with neither mutual connections nor shared skills is excluded at the
        // candidate-selection stage, not just filtered out at scoring.
        var repo = new InMemorySuggestionRepository();
        var noSignal = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);
        repo.SeedUser(noSignal);
        repo.SeedProfile(noSignal.Id, ["Java"]);  // no overlap

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        Assert.Equal(0, result.TotalCount);
    }

    [Fact]
    public async Task Weights_ReadFromSettings_HighMutualWeightChangesScore()
    {
        var repo = new InMemorySuggestionRepository();
        var friend = Guid.NewGuid();
        var candidate = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);
        repo.SeedUser(candidate);
        repo.SeedProfile(candidate.Id, ["React"]);
        repo.SeedConnection(Me, friend, ConnectionStatus.Accepted);
        repo.SeedConnection(candidate.Id, friend, ConnectionStatus.Accepted);

        var settings = new SuggestionSettings { MutualConnectionWeight = 100, SharedSkillWeight = 5 };
        var sut = BuildSut(repo, settings);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.Equal(105, row.Score);   // 1 mutual × 100 + 1 skill × 5
    }

    [Fact]
    public async Task MaxCandidates_IsRespected()
    {
        var repo = new InMemorySuggestionRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);

        for (var i = 0; i < 10; i++)
        {
            var u = MakeUser(createdAt: DateTime.UtcNow.AddMinutes(-i));
            repo.SeedUser(u);
            repo.SeedProfile(u.Id, ["React"]);
        }

        var settings = new SuggestionSettings { MaxCandidates = 3 };
        var sut = BuildSut(repo, settings);
        var result = await sut.GetSuggestionsAsync(Me, 1, 50);

        Assert.True(result.TotalCount <= 3);
    }

    [Fact]
    public async Task DualSignalCandidate_AppearsExactlyOnce()
    {
        // A user reachable via BOTH FOF and skill-overlap must be de-duplicated to one entry.
        var repo = new InMemorySuggestionRepository();
        var friend = Guid.NewGuid();
        var candidate = MakeUser();

        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);
        repo.SeedUser(candidate);
        repo.SeedProfile(candidate.Id, ["React"]);          // skill match
        repo.SeedConnection(Me, friend, ConnectionStatus.Accepted);
        repo.SeedConnection(candidate.Id, friend, ConnectionStatus.Accepted);  // FOF match

        var sut = BuildSut(repo);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.Equal(candidate.Id, row.UserId);
        Assert.Equal(15, row.Score);    // 1 mutual × 10 + 1 skill × 5
    }

    [Fact]
    public async Task NoOpCache_DoesNotServeStaleResults()
    {
        // If caching were active and un-invalidated, the second call would return the
        // cached (empty) result. With NoOpSuggestionCache every call hits the repository.
        var repo = new InMemorySuggestionRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);

        var sut = BuildSut(repo);

        var result1 = await sut.GetSuggestionsAsync(Me, 1, 10);
        Assert.Empty(result1.Items);

        // Seed a new skill-matching candidate between calls
        var candidate = MakeUser();
        repo.SeedUser(candidate);
        repo.SeedProfile(candidate.Id, ["React"]);

        var result2 = await sut.GetSuggestionsAsync(Me, 1, 10);
        Assert.Single(result2.Items);   // Repo was called, not a stale cache hit
    }

    [Fact]
    public async Task CustomScorer_OrderingFollowsScorer()
    {
        // ISuggestionScorer is honored: a fake scorer controls the ranking
        // independently of the weighted arithmetic.
        var repo = new InMemorySuggestionRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedProfile(Me, ["React"]);

        var candidateA = MakeUser();
        var candidateB = MakeUser();
        repo.SeedUser(candidateA);
        repo.SeedProfile(candidateA.Id, ["React"]);
        repo.SeedUser(candidateB);
        repo.SeedProfile(candidateB.Id, ["React"]);

        // B gets 100, A gets 1 — so B should rank first
        var scorer = new FixedScorer(new Dictionary<Guid, int>
        {
            [candidateA.Id] = 1,
            [candidateB.Id] = 100
        });

        var sut = BuildSut(repo, scorer: scorer);
        var result = await sut.GetSuggestionsAsync(Me, 1, 10);

        Assert.Equal(2, result.Items.Count);
        Assert.Equal(candidateB.Id, result.Items[0].UserId);   // score 100
        Assert.Equal(candidateA.Id, result.Items[1].UserId);   // score 1
    }

    // ===== HELPERS =====

    private static User MakeUser(Guid? id = null, DateTime? createdAt = null) => new()
    {
        Id = id ?? Guid.NewGuid(),
        FullName = "Test User",
        Email = $"{Guid.NewGuid()}@test.com",
        CreatedAt = createdAt ?? DateTime.UtcNow,
        SecurityStamp = Guid.NewGuid()
    };

    // ===== FAKES =====

    private sealed class FixedScorer(Dictionary<Guid, int> scores) : ISuggestionScorer
    {
        public int Score(SuggestionCandidate candidate) =>
            scores.GetValueOrDefault(candidate.UserId, 0);
    }

    private sealed class InMemorySuggestionRepository : ISuggestionRepository
    {
        private readonly List<User> _users = [];
        private readonly Dictionary<Guid, List<string>> _skills = [];
        private readonly List<Connection> _connections = [];
        private readonly List<SuggestionDismissal> _dismissals = [];

        public void SeedUser(User user) => _users.Add(user);
        public void SeedProfile(Guid userId, List<string> skills) => _skills[userId] = skills;
        public void SeedConnection(Guid requesterId, Guid receiverId, ConnectionStatus status) =>
            _connections.Add(new Connection
            {
                Id = Guid.NewGuid(), RequesterId = requesterId,
                ReceiverId = receiverId, Status = status, CreatedAt = DateTime.UtcNow
            });

        public Task<List<(User User, Profile? Profile)>> GetCandidatesAsync(
            Guid meId, IReadOnlyList<string> mySkillsLower, int cap, CancellationToken ct)
        {
            var nonRejectedIds = _connections
                .Where(c => (c.RequesterId == meId || c.ReceiverId == meId)
                         && c.Status != ConnectionStatus.Rejected)
                .Select(c => c.RequesterId == meId ? c.ReceiverId : c.RequesterId)
                .ToHashSet();

            var dismissedIds = _dismissals
                .Where(d => d.UserId == meId && d.Kind == SuggestionKind.Connect)
                .Select(d => d.DismissedUserId)
                .ToHashSet();

            // Mirror Query A: FOF (friends-of-friends)
            var myFriendIds = _connections
                .Where(c => c.Status == ConnectionStatus.Accepted &&
                           (c.RequesterId == meId || c.ReceiverId == meId))
                .Select(c => c.RequesterId == meId ? c.ReceiverId : c.RequesterId)
                .ToHashSet();

            var fofIds = _connections
                .Where(c => c.Status == ConnectionStatus.Accepted &&
                           (myFriendIds.Contains(c.RequesterId) || myFriendIds.Contains(c.ReceiverId)) &&
                           c.RequesterId != meId && c.ReceiverId != meId)
                .SelectMany(c => new[] { c.RequesterId, c.ReceiverId })
                .Where(id => id != meId && !myFriendIds.Contains(id))
                .ToHashSet();

            // Mirror Query B: skill-overlap (case-insensitive)
            var skillIds = new HashSet<Guid>();
            if (mySkillsLower.Count > 0)
            {
                skillIds = _users
                    .Where(u => u.Id != meId && _skills.TryGetValue(u.Id, out var sk) &&
                               sk.Any(s => mySkillsLower.Contains(s.ToLower())))
                    .Select(u => u.Id)
                    .ToHashSet();
            }

            var signalIds = fofIds.Union(skillIds).ToHashSet();

            var candidates = _users
                .Where(u => u.Id != meId
                         && !nonRejectedIds.Contains(u.Id)
                         && !dismissedIds.Contains(u.Id)
                         && signalIds.Contains(u.Id))
                .Take(cap)
                .Select(u =>
                {
                    Profile? profile = _skills.TryGetValue(u.Id, out var skills)
                        ? new Profile { UserId = u.Id, Skills = skills }
                        : null;
                    return (u, profile);
                })
                .ToList();

            return Task.FromResult(candidates);
        }

        public Task<List<string>> GetMySkillsAsync(Guid meId, CancellationToken ct) =>
            Task.FromResult(_skills.GetValueOrDefault(meId, []));

        public Task<HashSet<Guid>> GetMyAcceptedConnectionIdsAsync(Guid meId, CancellationToken ct)
        {
            var ids = _connections
                .Where(c => c.Status == ConnectionStatus.Accepted &&
                           (c.RequesterId == meId || c.ReceiverId == meId))
                .Select(c => c.RequesterId == meId ? c.ReceiverId : c.RequesterId)
                .ToHashSet();
            return Task.FromResult(ids);
        }

        public Task<Dictionary<Guid, HashSet<Guid>>> GetCandidateConnectionIdsAsync(
            IReadOnlyList<Guid> candidateIds, CancellationToken ct)
        {
            var dict = candidateIds.ToDictionary(id => id, _ => new HashSet<Guid>());
            foreach (var c in _connections.Where(c => c.Status == ConnectionStatus.Accepted))
            {
                if (dict.TryGetValue(c.RequesterId, out var setA)) setA.Add(c.ReceiverId);
                if (dict.TryGetValue(c.ReceiverId, out var setB)) setB.Add(c.RequesterId);
            }
            return Task.FromResult(dict);
        }

        public Task DismissAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct)
        {
            if (!_dismissals.Any(d => d.UserId == meId && d.DismissedUserId == dismissedUserId && d.Kind == kind))
                _dismissals.Add(new SuggestionDismissal
                {
                    Id = Guid.NewGuid(), UserId = meId,
                    DismissedUserId = dismissedUserId, Kind = kind, CreatedAt = DateTime.UtcNow
                });
            return Task.CompletedTask;
        }

        public Task UndismissAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct)
        {
            _dismissals.RemoveAll(d => d.UserId == meId && d.DismissedUserId == dismissedUserId && d.Kind == kind);
            return Task.CompletedTask;
        }

        public bool HasKindDismissal(Guid meId, Guid userId, SuggestionKind kind) =>
            _dismissals.Any(d => d.UserId == meId && d.DismissedUserId == userId && d.Kind == kind);
    }

    // ===== INDEPENDENCE: connect-dismiss does not touch follow-dismiss =====

    [Fact]
    public async Task ConnectDismiss_DoesNotCreateFollowDismissal()
    {
        // After dismissing via SuggestionService (Kind=Connect), the dismissal store
        // must NOT contain a Kind=Follow entry for the same pair.
        // This proves connect-dismiss and follow-dismiss are independent kinds.
        var repo = new InMemorySuggestionRepository();
        var target = Guid.NewGuid();
        var sut = BuildSut(repo);

        await sut.DismissAsync(Me, target);

        Assert.True(repo.HasKindDismissal(Me, target, SuggestionKind.Connect));
        Assert.False(repo.HasKindDismissal(Me, target, SuggestionKind.Follow));
    }
}
