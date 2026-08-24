using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Application.Features.Network.Services;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Tests.Network;

public class FollowSuggestionTests
{
    private static readonly Guid Me = Guid.NewGuid();

    // ===== Helpers =====

    private static FollowService BuildSut(InMemoryFollowRepository repo, SuggestionSettings? settings = null)
    {
        settings ??= new SuggestionSettings();
        var scorer = new WeightedFollowSuggestionScorer(Options.Create(settings));
        return new FollowService(repo, scorer, Options.Create(settings), NullLogger<FollowService>.Instance);
    }

    private static User MakeUser(Guid? id = null, string name = "Test User") =>
        new() { Id = id ?? Guid.NewGuid(), FullName = name, Email = $"{Guid.NewGuid()}@test.com", SecurityStamp = Guid.NewGuid() };

    // ===== Tests =====

    [Fact]
    public async Task ColdStart_UserWithNoConnectionsOrSkills_GetsGloballyPopularUsers()
    {
        // A brand-new user (no connections, no skills, no follows) still receives
        // results from Query C (global popularity). This is the cold-start guarantee.
        var repo = new InMemoryFollowRepository();
        var popular = MakeUser(name: "Popular Person");
        var lessPopular = MakeUser(name: "Less Popular");
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(popular);
        repo.SeedUser(lessPopular);

        // popular has 5 followers from strangers; lessPopular has 2
        for (var i = 0; i < 5; i++) repo.SeedFollow(Guid.NewGuid(), popular.Id);
        for (var i = 0; i < 2; i++) repo.SeedFollow(Guid.NewGuid(), lessPopular.Id);

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        Assert.Equal(2, result.Items.Count);
        Assert.Equal(popular.Id, result.Items[0].UserId);
        Assert.Equal(lessPopular.Id, result.Items[1].UserId);
    }

    [Fact]
    public async Task AlreadyFollowed_UsersAreExcluded()
    {
        var repo = new InMemoryFollowRepository();
        var followed = MakeUser();
        var other = MakeUser();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(followed);
        repo.SeedUser(other);

        // Me already follows 'followed'
        repo.SeedFollow(Me, followed.Id);
        // Both are popular so they'd normally qualify via Query C
        for (var i = 0; i < 5; i++) repo.SeedFollow(Guid.NewGuid(), followed.Id);
        for (var i = 0; i < 3; i++) repo.SeedFollow(Guid.NewGuid(), other.Id);

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        Assert.DoesNotContain(result.Items, r => r.UserId == followed.Id);
        Assert.Contains(result.Items, r => r.UserId == other.Id);
    }

    [Fact]
    public async Task Self_IsExcluded()
    {
        var repo = new InMemoryFollowRepository();
        var other = MakeUser();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(other);

        // Me is popular (many strangers follow Me)
        for (var i = 0; i < 10; i++) repo.SeedFollow(Guid.NewGuid(), Me);
        for (var i = 0; i < 3; i++) repo.SeedFollow(Guid.NewGuid(), other.Id);

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        Assert.DoesNotContain(result.Items, r => r.UserId == Me);
        Assert.Contains(result.Items, r => r.UserId == other.Id);
    }

    [Fact]
    public async Task Connected_ButNotFollowed_IsIncluded()
    {
        // Follow and Connection are independent — an accepted connection is NOT
        // excluded from follow suggestions (unlike connect-suggestions, which
        // excludes existing connections). A user may want to both connect with and
        // follow someone; the two actions do not imply each other.
        var repo = new InMemoryFollowRepository();
        var connectedUser = MakeUser();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(connectedUser);

        repo.SeedConnection(Me, connectedUser.Id, ConnectionStatus.Accepted);
        // connectedUser qualifies via Query C
        for (var i = 0; i < 3; i++) repo.SeedFollow(Guid.NewGuid(), connectedUser.Id);

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        Assert.Contains(result.Items, r => r.UserId == connectedUser.Id);
    }

    [Fact]
    public async Task SocialReach_CandidateFollowedByMoreConnections_ScoresHigher()
    {
        var connA = Guid.NewGuid();
        var connB = Guid.NewGuid();
        var candidateHigh = MakeUser(name: "High Reach");
        var candidateLow = MakeUser(name: "Low Reach");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidateHigh);
        repo.SeedUser(candidateLow);
        repo.SeedUser(MakeUser(connA));
        repo.SeedUser(MakeUser(connB));

        repo.SeedConnection(Me, connA, ConnectionStatus.Accepted);
        repo.SeedConnection(Me, connB, ConnectionStatus.Accepted);

        // candidateHigh is followed by both connections (SocialReach = 2)
        repo.SeedFollow(connA, candidateHigh.Id);
        repo.SeedFollow(connB, candidateHigh.Id);
        // candidateLow is followed by neither (SocialReach = 0)
        // Both need followers from strangers so they qualify via Query C too
        for (var i = 0; i < 2; i++) repo.SeedFollow(Guid.NewGuid(), candidateHigh.Id);
        for (var i = 0; i < 2; i++) repo.SeedFollow(Guid.NewGuid(), candidateLow.Id);

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        Assert.Equal(candidateHigh.Id, result.Items[0].UserId);
        Assert.True(result.Items[0].Score > result.Items.First(x => x.UserId == candidateLow.Id).Score);
    }

    [Fact]
    public async Task SkillOverlap_IsCaseInsensitive()
    {
        var repo = new InMemoryFollowRepository();
        var candidate = MakeUser();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);
        repo.SeedProfile(Me, ["Flutter"]);
        repo.SeedProfile(candidate.Id, ["flutter"]); // lowercase

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.NotEmpty(row.SharedSkills);
    }

    [Fact]
    public async Task SharedSkills_Response_ContainsActualOverlappingNames()
    {
        var repo = new InMemoryFollowRepository();
        var candidate = MakeUser();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);
        repo.SeedProfile(Me, ["React", "TypeScript"]);
        // candidate has "react" (lowercase) and "TypeScript" matching, plus "Go" (no overlap)
        repo.SeedProfile(candidate.Id, ["react", "TypeScript", "Go"]);

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var row = Assert.Single(result.Items);
        Assert.Equal(2, row.SharedSkills.Count);
        // Candidate's original casing is preserved
        Assert.Contains("react", row.SharedSkills);
        Assert.Contains("TypeScript", row.SharedSkills);
        Assert.DoesNotContain("Go", row.SharedSkills);
    }

    [Fact]
    public async Task FollowersCount_IsCorrectPerCandidate()
    {
        var repo = new InMemoryFollowRepository();
        var candidateA = MakeUser(name: "A");
        var candidateB = MakeUser(name: "B");
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidateA);
        repo.SeedUser(candidateB);

        for (var i = 0; i < 3; i++) repo.SeedFollow(Guid.NewGuid(), candidateA.Id);
        for (var i = 0; i < 5; i++) repo.SeedFollow(Guid.NewGuid(), candidateB.Id);

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var rowA = result.Items.Single(x => x.UserId == candidateA.Id);
        var rowB = result.Items.Single(x => x.UserId == candidateB.Id);
        Assert.Equal(3, rowA.FollowersCount);
        Assert.Equal(5, rowB.FollowersCount);
    }

    [Fact]
    public async Task PopularityCap_Binds_StrongSocialSignalOutranksHighFollowers()
    {
        // Settings: SocialReachWeight=15, MaxPopularityBonus=10
        // candidateA: SocialReach=2, FollowersCount=1
        //   score = 2*15 + min(1,10) = 31
        // candidateB: SocialReach=0, FollowersCount=10000
        //   score = 0 + min(10000,10) = 10  ← cap binds here
        var settings = new SuggestionSettings
        {
            SocialReachWeight = 15,
            SharedSkillWeight = 5,
            MaxPopularityBonus = 10,
            TopPopularCandidates = 100
        };

        var connA = Guid.NewGuid();
        var connB = Guid.NewGuid();
        var candidateA = MakeUser(name: "Strong Reach");
        var candidateB = MakeUser(name: "Mega Popular");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidateA);
        repo.SeedUser(candidateB);
        repo.SeedUser(MakeUser(connA));
        repo.SeedUser(MakeUser(connB));

        repo.SeedConnection(Me, connA, ConnectionStatus.Accepted);
        repo.SeedConnection(Me, connB, ConnectionStatus.Accepted);
        repo.SeedFollow(connA, candidateA.Id);
        repo.SeedFollow(connB, candidateA.Id);
        repo.SeedFollow(Guid.NewGuid(), candidateA.Id); // 1 stranger follower

        // candidateB: 10000 simulated followers (use a smaller number for performance)
        for (var i = 0; i < 50; i++) repo.SeedFollow(Guid.NewGuid(), candidateB.Id);

        var sut = BuildSut(repo, settings);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var rowA = result.Items.Single(x => x.UserId == candidateA.Id);
        var rowB = result.Items.Single(x => x.UserId == candidateB.Id);

        Assert.True(rowA.Score > rowB.Score, $"Expected A ({rowA.Score}) > B ({rowB.Score})");
        // Confirm the cap actually binds for B (50 followers > MaxPopularityBonus=10)
        Assert.True(rowB.FollowersCount > settings.MaxPopularityBonus);
        Assert.Equal(settings.MaxPopularityBonus, rowB.Score);
        // A is ranked first
        Assert.Equal(candidateA.Id, result.Items[0].UserId);
    }

    [Fact]
    public async Task Weights_FromSettings_ChangeOrdering()
    {
        // candidateA: SocialReach=2, SharedSkills=0
        // candidateB: SocialReach=0, SharedSkills=4
        // Default (SocialReachWeight=15): A=30, B=20 → A first
        // Modified (SocialReachWeight=0): A=0,  B=20 → B first

        var connA = Guid.NewGuid();
        var connB = Guid.NewGuid();
        var candidateA = MakeUser(name: "Social");
        var candidateB = MakeUser(name: "Skills");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidateA);
        repo.SeedUser(candidateB);
        repo.SeedUser(MakeUser(connA));
        repo.SeedUser(MakeUser(connB));

        repo.SeedProfile(Me, ["React", "TS", "Go", "Rust"]);
        repo.SeedProfile(candidateB.Id, ["react", "ts", "go", "rust"]); // 4 shared skills

        repo.SeedConnection(Me, connA, ConnectionStatus.Accepted);
        repo.SeedConnection(Me, connB, ConnectionStatus.Accepted);
        repo.SeedFollow(connA, candidateA.Id);
        repo.SeedFollow(connB, candidateA.Id);
        // Both need at least one follower from Query C
        repo.SeedFollow(Guid.NewGuid(), candidateA.Id);
        repo.SeedFollow(Guid.NewGuid(), candidateB.Id);

        // Default settings: SocialReachWeight=15
        var defaultSettings = new SuggestionSettings { SocialReachWeight = 15, SharedSkillWeight = 5, MaxPopularityBonus = 10, TopPopularCandidates = 100 };
        var result1 = await BuildSut(repo, defaultSettings).GetFollowSuggestionsAsync(Me, 1, 10);
        Assert.Equal(candidateA.Id, result1.Items[0].UserId);

        // Zero-out social reach weight — B should rise to the top
        var zeroReachSettings = new SuggestionSettings { SocialReachWeight = 0, SharedSkillWeight = 5, MaxPopularityBonus = 0, TopPopularCandidates = 100 };
        var result2 = await BuildSut(repo, zeroReachSettings).GetFollowSuggestionsAsync(Me, 1, 10);
        Assert.Equal(candidateB.Id, result2.Items[0].UserId);
    }

    [Fact]
    public async Task DuplicateCandidateFromMultipleQueries_AppearsExactlyOnce()
    {
        // candidateA qualifies via both Query A (followed by my connection)
        // and Query C (globally popular). Must appear exactly once.
        var conn = Guid.NewGuid();
        var candidateA = MakeUser(name: "Dual Signal");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidateA);
        repo.SeedUser(MakeUser(conn));

        repo.SeedConnection(Me, conn, ConnectionStatus.Accepted);
        repo.SeedFollow(conn, candidateA.Id); // Query A signal
        for (var i = 0; i < 5; i++) repo.SeedFollow(Guid.NewGuid(), candidateA.Id); // Query C signal

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        Assert.Equal(1, result.Items.Count(x => x.UserId == candidateA.Id));
    }

    [Fact]
    public async Task Ordering_IsDeterministic_AcrossIdenticalCalls()
    {
        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));

        // Create several candidates with the same score (no skills, no social reach)
        var candidates = Enumerable.Range(0, 5).Select(_ => MakeUser()).ToList();
        foreach (var c in candidates)
        {
            repo.SeedUser(c);
            repo.SeedFollow(Guid.NewGuid(), c.Id); // all have 1 follower → same score
        }

        var sut = BuildSut(repo);
        var result1 = await sut.GetFollowSuggestionsAsync(Me, 1, 10);
        var result2 = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        Assert.Equal(
            result1.Items.Select(x => x.UserId),
            result2.Items.Select(x => x.UserId));
    }

    [Fact]
    public async Task Pagination_PageSizeClampedTo50_Page2ReturnsNextSlice_NoOverlap()
    {
        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));

        for (var i = 0; i < 60; i++)
        {
            var u = MakeUser();
            repo.SeedUser(u);
            repo.SeedFollow(Guid.NewGuid(), u.Id);
        }

        var sut = BuildSut(repo);

        var page1 = await sut.GetFollowSuggestionsAsync(Me, 1, 1000); // clamps to 50
        Assert.Equal(FollowService.MaxPageSize, page1.Items.Count);
        Assert.Equal(FollowService.MaxPageSize, page1.PageSize);
        Assert.Equal(60, page1.TotalCount);

        var page2 = await sut.GetFollowSuggestionsAsync(Me, 2, FollowService.MaxPageSize);
        Assert.Equal(10, page2.Items.Count);
        Assert.Equal(60, page2.TotalCount);

        var page1Ids = page1.Items.Select(x => x.UserId).ToHashSet();
        Assert.All(page2.Items, item => Assert.DoesNotContain(item.UserId, page1Ids));
    }

    // ===== Social proof preview (N6b) =====

    [Fact]
    public async Task SocialProof_TwoConnectionsFollowCandidate_PreviewHasTwoEntries()
    {
        var connA = MakeUser(name: "Alice");
        var connB = MakeUser(name: "Bob");
        var candidate = MakeUser(name: "Candidate");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(connA);
        repo.SeedUser(connB);
        repo.SeedUser(candidate);

        repo.SeedConnection(Me, connA.Id, ConnectionStatus.Accepted);
        repo.SeedConnection(Me, connB.Id, ConnectionStatus.Accepted);
        repo.SeedFollow(connA.Id, candidate.Id);
        repo.SeedFollow(connB.Id, candidate.Id);
        repo.SeedFollow(Guid.NewGuid(), candidate.Id); // stranger — for Query C

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var row = result.Items.Single(x => x.UserId == candidate.Id);
        Assert.Equal(2, row.FollowedByPreview.Count);
    }

    [Fact]
    public async Task SocialProof_FiveConnectionsFollowCandidate_PreviewCappedAtThree()
    {
        var connections = Enumerable.Range(0, 5)
            .Select(i => MakeUser(name: $"Conn{i:D2}"))
            .ToList();
        var candidate = MakeUser(name: "Popular");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);
        foreach (var c in connections)
        {
            repo.SeedUser(c);
            repo.SeedConnection(Me, c.Id, ConnectionStatus.Accepted);
            repo.SeedFollow(c.Id, candidate.Id);
        }
        repo.SeedFollow(Guid.NewGuid(), candidate.Id); // for Query C

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var row = result.Items.Single(x => x.UserId == candidate.Id);
        Assert.Equal(3, row.FollowedByPreview.Count); // capped at 3
    }

    [Fact]
    public async Task SocialProof_ZeroConnectionsFollowCandidate_PreviewIsEmptyNotNull()
    {
        var candidate = MakeUser(name: "No Proof");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);
        repo.SeedFollow(Guid.NewGuid(), candidate.Id); // stranger only — for Query C

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var row = result.Items.Single(x => x.UserId == candidate.Id);
        Assert.NotNull(row.FollowedByPreview);
        Assert.Empty(row.FollowedByPreview);
    }

    [Fact]
    public async Task SocialProof_PreviewNeverContainsMeOrTheCandidate()
    {
        var conn = MakeUser(name: "Charlie");
        var candidate = MakeUser(name: "Dave");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(conn);
        repo.SeedUser(candidate);

        repo.SeedConnection(Me, conn.Id, ConnectionStatus.Accepted);
        repo.SeedFollow(conn.Id, candidate.Id);
        // Me also follows the candidate — Me is NOT a connection of himself so won't appear in preview
        repo.SeedFollow(Me, candidate.Id); // already-following → candidate excluded... actually Me follows candidate so candidate is excluded
        // Redo: Me doesn't follow candidate so it qualifies. Let strangers drive Query C.
        repo.SeedFollow(Guid.NewGuid(), candidate.Id);

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var row = result.Items.FirstOrDefault(x => x.UserId == candidate.Id);
        if (row is null) return; // Me follows candidate → rightly excluded

        Assert.DoesNotContain(row.FollowedByPreview, p => p.UserId == Me);
        Assert.DoesNotContain(row.FollowedByPreview, p => p.UserId == candidate.Id);
    }

    [Fact]
    public async Task SocialProof_PreviewOrderIsDeterministicByFullName()
    {
        var connZ = MakeUser(name: "Zara");
        var connA = MakeUser(name: "Alice");
        var connM = MakeUser(name: "Mike");
        var candidate = MakeUser(name: "Candidate");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(connZ);
        repo.SeedUser(connA);
        repo.SeedUser(connM);
        repo.SeedUser(candidate);

        repo.SeedConnection(Me, connZ.Id, ConnectionStatus.Accepted);
        repo.SeedConnection(Me, connA.Id, ConnectionStatus.Accepted);
        repo.SeedConnection(Me, connM.Id, ConnectionStatus.Accepted);
        repo.SeedFollow(connZ.Id, candidate.Id);
        repo.SeedFollow(connA.Id, candidate.Id);
        repo.SeedFollow(connM.Id, candidate.Id);
        repo.SeedFollow(Guid.NewGuid(), candidate.Id); // for Query C

        var sut = BuildSut(repo);
        var r1 = await sut.GetFollowSuggestionsAsync(Me, 1, 10);
        var r2 = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var preview1 = r1.Items.Single(x => x.UserId == candidate.Id).FollowedByPreview;
        var preview2 = r2.Items.Single(x => x.UserId == candidate.Id).FollowedByPreview;

        Assert.Equal(preview1.Select(p => p.UserId), preview2.Select(p => p.UserId));
        // Ordered by FullName: Alice, Mike, Zara
        Assert.Equal("Alice", preview1[0].FullName);
        Assert.Equal("Mike", preview1[1].FullName);
        Assert.Equal("Zara", preview1[2].FullName);
    }

    [Fact]
    public async Task SocialProof_NonConnectionFollower_ExcludedFromCountAndPreview()
    {
        var conn = MakeUser(name: "MyFriend");
        var stranger = MakeUser(name: "Stranger");
        var candidate = MakeUser(name: "Target");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(conn);
        repo.SeedUser(stranger);
        repo.SeedUser(candidate);

        repo.SeedConnection(Me, conn.Id, ConnectionStatus.Accepted);
        repo.SeedFollow(conn.Id, candidate.Id);     // connection follower — counts
        repo.SeedFollow(stranger.Id, candidate.Id); // stranger — must NOT count or appear
        repo.SeedFollow(Guid.NewGuid(), candidate.Id); // for Query C

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        var row = result.Items.Single(x => x.UserId == candidate.Id);
        // Only 1 connection follower → count drives score; preview has exactly 1
        Assert.Single(row.FollowedByPreview);
        Assert.Equal(conn.Id, row.FollowedByPreview[0].UserId);
        Assert.DoesNotContain(row.FollowedByPreview, p => p.UserId == stranger.Id);
    }

    // ===== Follow-dismiss (N6b) =====

    [Fact]
    public async Task FollowDismiss_RemovesUserFromFollowSuggestions()
    {
        var candidate = MakeUser(name: "Target");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);
        repo.SeedFollow(Guid.NewGuid(), candidate.Id); // popular via Query C

        var sut = BuildSut(repo);
        await sut.DismissFollowSuggestionAsync(Me, candidate.Id);

        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);
        Assert.DoesNotContain(result.Items, r => r.UserId == candidate.Id);
    }

    [Fact]
    public async Task FollowDismiss_WritesKindFollow_NotKindConnect()
    {
        var candidate = MakeUser(name: "Target");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);

        var sut = BuildSut(repo);
        await sut.DismissFollowSuggestionAsync(Me, candidate.Id);

        Assert.True(repo.HasFollowDismissal(Me, candidate.Id));
        Assert.False(repo.HasConnectDismissal(Me, candidate.Id));
    }

    [Fact]
    public async Task ConnectDismiss_DoesNotRemoveFromFollowSuggestions()
    {
        // A connect-dismiss (Kind=Connect) must NOT affect the follow-suggestion feed.
        // Simulated by seeding Kind=Connect directly into InMemoryFollowRepository.
        var candidate = MakeUser(name: "Target");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);
        repo.SeedFollow(Guid.NewGuid(), candidate.Id); // popular via Query C

        repo.SeedConnectDismissal(Me, candidate.Id); // Kind=Connect, should be ignored by follow-suggestions

        var sut = BuildSut(repo);
        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);

        Assert.Contains(result.Items, r => r.UserId == candidate.Id);
    }

    [Fact]
    public async Task FollowDismiss_AlsoExcludesViaGlobalPopularityPath()
    {
        // The follow-dismiss must exclude the user from ALL three queries,
        // including Query C (global popularity / cold-start path).
        var candidate = MakeUser(name: "MegaPopular");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);
        for (var i = 0; i < 20; i++) repo.SeedFollow(Guid.NewGuid(), candidate.Id); // very popular → top of Query C

        var sut = BuildSut(repo);
        await sut.DismissFollowSuggestionAsync(Me, candidate.Id);

        var result = await sut.GetFollowSuggestionsAsync(Me, 1, 10);
        Assert.DoesNotContain(result.Items, r => r.UserId == candidate.Id);
    }

    [Fact]
    public async Task FollowDismissTwice_IsIdempotent()
    {
        var candidate = MakeUser(name: "Target");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);

        var sut = BuildSut(repo);
        await sut.DismissFollowSuggestionAsync(Me, candidate.Id);
        var ex = await Record.ExceptionAsync(() => sut.DismissFollowSuggestionAsync(Me, candidate.Id));

        Assert.Null(ex);
    }

    [Fact]
    public async Task FollowDismissThenUndismiss_UserReappearsInFollowSuggestions()
    {
        var candidate = MakeUser(name: "Target");

        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));
        repo.SeedUser(candidate);
        repo.SeedFollow(Guid.NewGuid(), candidate.Id);

        var sut = BuildSut(repo);
        await sut.DismissFollowSuggestionAsync(Me, candidate.Id);

        var afterDismiss = await sut.GetFollowSuggestionsAsync(Me, 1, 10);
        Assert.DoesNotContain(afterDismiss.Items, r => r.UserId == candidate.Id);

        await sut.UndismissFollowSuggestionAsync(Me, candidate.Id);

        var afterUndismiss = await sut.GetFollowSuggestionsAsync(Me, 1, 10);
        Assert.Contains(afterUndismiss.Items, r => r.UserId == candidate.Id);
    }

    [Fact]
    public async Task FollowDismissSelf_Throws400()
    {
        var repo = new InMemoryFollowRepository();
        repo.SeedUser(MakeUser(Me));

        var sut = BuildSut(repo);

        await Assert.ThrowsAsync<ValidationException>(() => sut.DismissFollowSuggestionAsync(Me, Me));
    }

    // ===== In-memory repository =====

    private sealed class InMemoryFollowRepository : IFollowRepository
    {
        private readonly List<Follow> _follows = [];
        private readonly Dictionary<Guid, User> _users = [];
        private readonly Dictionary<Guid, Profile> _profiles = [];
        private readonly List<(Guid RequesterId, Guid ReceiverId, ConnectionStatus Status)> _connections = [];
        private readonly List<(Guid UserId, Guid DismissedUserId, SuggestionKind Kind)> _dismissals = [];

        public void SeedUser(User u) => _users[u.Id] = u;

        public void SeedProfile(Guid userId, List<string> skills, string? headline = null, string? photoUrl = null) =>
            _profiles[userId] = new Profile
            {
                Id = Guid.NewGuid(), UserId = userId,
                Skills = skills, Headline = headline, ProfilePhotoUrl = photoUrl
            };

        public void SeedFollow(Guid followerId, Guid followeeId) =>
            _follows.Add(new Follow
            {
                Id = Guid.NewGuid(), FollowerId = followerId, FolloweeId = followeeId
            });

        public void SeedConnection(Guid requesterId, Guid receiverId, ConnectionStatus status) =>
            _connections.Add((requesterId, receiverId, status));

        // ── Test-assertion helpers ───────────────────────────────────────────

        public bool HasFollowDismissal(Guid meId, Guid userId) =>
            _dismissals.Any(d => d.UserId == meId && d.DismissedUserId == userId && d.Kind == SuggestionKind.Follow);

        public bool HasConnectDismissal(Guid meId, Guid userId) =>
            _dismissals.Any(d => d.UserId == meId && d.DismissedUserId == userId && d.Kind == SuggestionKind.Connect);

        public void SeedConnectDismissal(Guid meId, Guid userId) =>
            _dismissals.Add((meId, userId, SuggestionKind.Connect));

        // ── Existing interface methods ────────────────────────────────────────

        public Task FollowAsync(Guid followerId, Guid followeeId, CancellationToken ct)
        {
            SeedFollow(followerId, followeeId);
            return Task.CompletedTask;
        }

        public Task UnfollowAsync(Guid followerId, Guid followeeId, CancellationToken ct)
        {
            _follows.RemoveAll(f => f.FollowerId == followerId && f.FolloweeId == followeeId);
            return Task.CompletedTask;
        }

        public Task<bool> UserExistsAsync(Guid userId, CancellationToken ct) =>
            Task.FromResult(_users.ContainsKey(userId));

        public Task<PagedResult<FollowUserResponse>> GetFollowersAsync(
            Guid meId, int page, int pageSize, CancellationToken ct) =>
            Task.FromResult(new PagedResult<FollowUserResponse>
                { Items = [], Page = page, PageSize = pageSize, TotalCount = 0 });

        public Task<PagedResult<FollowUserResponse>> GetFollowingAsync(
            Guid meId, int page, int pageSize, CancellationToken ct) =>
            Task.FromResult(new PagedResult<FollowUserResponse>
                { Items = [], Page = page, PageSize = pageSize, TotalCount = 0 });

        public Task<(bool IsFollowing, bool IsFollowedBy)> GetFollowStatusAsync(
            Guid meId, Guid targetId, CancellationToken ct) =>
            Task.FromResult((false, false));

        public Task<(int Following, int Followers)> GetFollowCountsAsync(Guid meId, CancellationToken ct) =>
            Task.FromResult((0, 0));

        // ── Suggestion-specific methods ───────────────────────────────────────

        public Task<List<Guid>> GetMyAcceptedConnectionIdsAsync(Guid meId, CancellationToken ct)
        {
            var ids = _connections
                .Where(c => c.Status == ConnectionStatus.Accepted &&
                           (c.RequesterId == meId || c.ReceiverId == meId))
                .Select(c => c.RequesterId == meId ? c.ReceiverId : c.RequesterId)
                .ToList();
            return Task.FromResult(ids);
        }

        public Task<List<string>> GetMySkillsAsync(Guid meId, CancellationToken ct) =>
            Task.FromResult(_profiles.TryGetValue(meId, out var p) ? p.Skills : new List<string>());

        public Task<List<Guid>> GetFollowSuggestionCandidateIdsAsync(
            Guid meId, IReadOnlyList<Guid> myConnectionIds, string[] mySkillsLower,
            int topPopularCount, CancellationToken ct)
        {
            var alreadyFollowing = _follows
                .Where(f => f.FollowerId == meId)
                .Select(f => f.FolloweeId)
                .ToHashSet();

            var followDismissed = _dismissals
                .Where(d => d.UserId == meId && d.Kind == SuggestionKind.Follow)
                .Select(d => d.DismissedUserId)
                .ToHashSet();

            // Query A: users followed by my accepted connections
            List<Guid> queryAIds = [];
            if (myConnectionIds.Count > 0)
            {
                queryAIds = _follows
                    .Where(f => myConnectionIds.Contains(f.FollowerId)
                             && f.FolloweeId != meId
                             && !alreadyFollowing.Contains(f.FolloweeId)
                             && !followDismissed.Contains(f.FolloweeId))
                    .Select(f => f.FolloweeId)
                    .Distinct()
                    .ToList();
            }

            // Query B: profiles with matching skills (case-insensitive)
            List<Guid> queryBIds = [];
            if (mySkillsLower.Length > 0)
            {
                var mySkillsSet = mySkillsLower.ToHashSet();
                queryBIds = _profiles
                    .Where(kvp => kvp.Key != meId
                               && !alreadyFollowing.Contains(kvp.Key)
                               && !followDismissed.Contains(kvp.Key)
                               && kvp.Value.Skills.Any(s => mySkillsSet.Contains(s.ToLower())))
                    .Select(kvp => kvp.Key)
                    .ToList();
            }

            // Query C: global popularity (cold-start path)
            var queryCIds = _follows
                .Where(f => f.FolloweeId != meId
                         && !alreadyFollowing.Contains(f.FolloweeId)
                         && !followDismissed.Contains(f.FolloweeId))
                .GroupBy(f => f.FolloweeId)
                .OrderByDescending(g => g.Count())
                .Take(topPopularCount)
                .Select(g => g.Key)
                .ToList();

            return Task.FromResult(queryAIds.Union(queryBIds).Union(queryCIds).ToList());
        }

        public Task<List<(User User, Profile? Profile)>> LoadFollowSuggestionDetailsAsync(
            IReadOnlyList<Guid> candidateIds, CancellationToken ct)
        {
            var results = candidateIds
                .Where(id => _users.ContainsKey(id))
                .Select(id =>
                {
                    _profiles.TryGetValue(id, out var profile);
                    return (_users[id], (Profile?)profile);
                })
                .ToList();
            return Task.FromResult(results);
        }

        public Task<Dictionary<Guid, int>> GetFollowerCountsForCandidatesAsync(
            IReadOnlyList<Guid> candidateIds, CancellationToken ct)
        {
            var counts = _follows
                .Where(f => candidateIds.Contains(f.FolloweeId))
                .GroupBy(f => f.FolloweeId)
                .ToDictionary(g => g.Key, g => g.Count());
            return Task.FromResult(counts);
        }

        public Task<Dictionary<Guid, SocialReachData>> GetSocialReachDataAsync(
            IReadOnlyList<Guid> candidateIds, IReadOnlyList<Guid> myConnectionIds, CancellationToken ct)
        {
            if (candidateIds.Count == 0 || myConnectionIds.Count == 0)
                return Task.FromResult(new Dictionary<Guid, SocialReachData>());

            var rows = _follows
                .Where(f => candidateIds.Contains(f.FolloweeId) && myConnectionIds.Contains(f.FollowerId))
                .Select(f =>
                {
                    _users.TryGetValue(f.FollowerId, out var user);
                    _profiles.TryGetValue(f.FollowerId, out var profile);
                    return new
                    {
                        CandidateId = f.FolloweeId,
                        FollowerId  = f.FollowerId,
                        FullName    = user?.FullName ?? "Unknown",
                        PhotoUrl    = profile?.ProfilePhotoUrl
                    };
                })
                .ToList();

            var result = rows
                .GroupBy(r => r.CandidateId)
                .ToDictionary(
                    g => g.Key,
                    g =>
                    {
                        var preview = g
                            .OrderBy(r => r.FullName)
                            .ThenBy(r => r.FollowerId)
                            .Take(3)
                            .Select(r => new SocialProofUser(r.FollowerId, r.FullName, r.PhotoUrl))
                            .ToList<SocialProofUser>();
                        return new SocialReachData(g.Count(), preview);
                    });

            return Task.FromResult(result);
        }

        public Task DismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct)
        {
            if (!_dismissals.Any(d => d.UserId == meId && d.DismissedUserId == dismissedUserId && d.Kind == kind))
                _dismissals.Add((meId, dismissedUserId, kind));
            return Task.CompletedTask;
        }

        public Task UndismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct)
        {
            _dismissals.RemoveAll(d => d.UserId == meId && d.DismissedUserId == dismissedUserId && d.Kind == kind);
            return Task.CompletedTask;
        }
    }
}
