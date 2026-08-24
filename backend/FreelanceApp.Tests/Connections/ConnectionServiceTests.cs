using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Connections.DTOs;
using FreelanceApp.Application.Features.Connections.Services;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging.Abstractions;

namespace FreelanceApp.Tests.Connections;

public class ConnectionServiceTests
{
    private static readonly Guid UserA = Guid.NewGuid();
    private static readonly Guid UserB = Guid.NewGuid();
    private static readonly Guid UserC = Guid.NewGuid();
    private static readonly Guid UserM1 = Guid.NewGuid();
    private static readonly Guid UserM2 = Guid.NewGuid();
    private static readonly Guid UserM3 = Guid.NewGuid();
    private static readonly Guid UserM4 = Guid.NewGuid();
    private static readonly Guid UserM5 = Guid.NewGuid();

    private static (ConnectionService sut, InMemoryConnectionRepository repo) BuildSut()
    {
        var users = new InMemoryUserRepository(
            new User { Id = UserA, FullName = "User A" },
            new User { Id = UserB, FullName = "User B" },
            new User { Id = UserC, FullName = "User C" });

        var repo = new InMemoryConnectionRepository(users);
        return (new ConnectionService(repo, users, NullLogger<ConnectionService>.Instance), repo);
    }

    private static (ConnectionService sut, InMemoryConnectionRepository repo) BuildMutualsSut()
    {
        var users = new InMemoryUserRepository(
            new User { Id = UserA, FullName = "User A" },
            new User { Id = UserB, FullName = "User B" },
            new User { Id = UserC, FullName = "User C" },
            new User { Id = UserM1, FullName = "Mutual 1" },
            new User { Id = UserM2, FullName = "Mutual 2" },
            new User { Id = UserM3, FullName = "Mutual 3" },
            new User { Id = UserM4, FullName = "Mutual 4" },
            new User { Id = UserM5, FullName = "Mutual 5" });
        var repo = new InMemoryConnectionRepository(users);
        return (new ConnectionService(repo, users, NullLogger<ConnectionService>.Instance), repo);
    }

    private static Connection Accepted(Guid a, Guid b) => new()
    {
        Id = Guid.NewGuid(), RequesterId = a, ReceiverId = b,
        Status = ConnectionStatus.Accepted, CreatedAt = DateTime.UtcNow
    };

    private static Connection Pending(Guid requester, Guid receiver) => new()
    {
        Id = Guid.NewGuid(), RequesterId = requester, ReceiverId = receiver,
        Status = ConnectionStatus.Pending, CreatedAt = DateTime.UtcNow
    };

    private static Connection Rejected(Guid a, Guid b) => new()
    {
        Id = Guid.NewGuid(), RequesterId = a, ReceiverId = b,
        Status = ConnectionStatus.Rejected, CreatedAt = DateTime.UtcNow
    };

    // ===== SEND =====

    [Fact]
    public async Task Send_Throws400_OnSelfRequest()
    {
        var (sut, _) = BuildSut();

        var ex = await Assert.ThrowsAsync<ValidationException>(
            () => sut.SendRequestAsync(UserA, UserA));

        Assert.Equal(400, ex.StatusCode);
    }

    [Fact]
    public async Task Send_Throws404_WhenReceiverDoesNotExist()
    {
        var (sut, _) = BuildSut();

        var ex = await Assert.ThrowsAsync<NotFoundException>(
            () => sut.SendRequestAsync(UserA, Guid.NewGuid()));

        Assert.Equal(404, ex.StatusCode);
    }

    [Fact]
    public async Task Send_Throws409_WhenSameDirectionPendingExists()
    {
        var (sut, _) = BuildSut();
        await sut.SendRequestAsync(UserA, UserB);

        var ex = await Assert.ThrowsAsync<ConflictException>(
            () => sut.SendRequestAsync(UserA, UserB));

        Assert.Equal(409, ex.StatusCode);
    }

    [Fact]
    public async Task Send_Throws409WithAcceptHint_WhenOppositePendingExists()
    {
        var (sut, _) = BuildSut();
        await sut.SendRequestAsync(UserA, UserB);

        // B tries to send back while A's request is still pending
        var ex = await Assert.ThrowsAsync<ConflictException>(
            () => sut.SendRequestAsync(UserB, UserA));

        Assert.Equal(409, ex.StatusCode);
        Assert.Contains("accept", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Send_Throws409_WhenAlreadyConnected_EitherDirection()
    {
        var (sut, _) = BuildSut();
        var request = await sut.SendRequestAsync(UserA, UserB);
        await sut.AcceptRequestAsync(UserB, request.Id);

        await Assert.ThrowsAsync<ConflictException>(() => sut.SendRequestAsync(UserA, UserB));
        await Assert.ThrowsAsync<ConflictException>(() => sut.SendRequestAsync(UserB, UserA));
    }

    [Fact]
    public async Task Send_ReusesRejectedRow_AsNewPending()
    {
        var (sut, repo) = BuildSut();
        var first = await sut.SendRequestAsync(UserA, UserB);
        await sut.RejectRequestAsync(UserB, first.Id);

        // Rejection ke baad dobara request — unique index ki wajah se wahi row reset hoti hai
        var second = await sut.SendRequestAsync(UserA, UserB);

        Assert.Equal(first.Id, second.Id);
        Assert.Equal(ConnectionStatus.Pending, second.Status);
        Assert.Null(second.RespondedAt);
        Assert.Single(repo.All);
    }

    // ===== ACCEPT / REJECT =====

    [Fact]
    public async Task Accept_Throws403_WhenCallerIsNotReceiver()
    {
        var (sut, _) = BuildSut();
        var request = await sut.SendRequestAsync(UserA, UserB);

        // C (teesra user) aur khud requester — dono forbidden
        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.AcceptRequestAsync(UserC, request.Id));
        Assert.Equal(403, ex.StatusCode);

        await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.AcceptRequestAsync(UserA, request.Id));
    }

    [Fact]
    public async Task Accept_Throws409_WhenAlreadyResponded()
    {
        var (sut, _) = BuildSut();
        var request = await sut.SendRequestAsync(UserA, UserB);
        await sut.AcceptRequestAsync(UserB, request.Id);

        var ex = await Assert.ThrowsAsync<ConflictException>(
            () => sut.AcceptRequestAsync(UserB, request.Id));

        Assert.Equal(409, ex.StatusCode);
    }

    // ===== WITHDRAW =====

    [Fact]
    public async Task Withdraw_Throws403_WhenCallerIsNotRequester()
    {
        var (sut, _) = BuildSut();
        var request = await sut.SendRequestAsync(UserA, UserB);

        await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.WithdrawRequestAsync(UserB, request.Id));
    }

    [Fact]
    public async Task Withdraw_RemovesPendingRequest_ForRequester()
    {
        var (sut, repo) = BuildSut();
        var request = await sut.SendRequestAsync(UserA, UserB);

        await sut.WithdrawRequestAsync(UserA, request.Id);

        Assert.Empty(repo.All);
        var status = await sut.GetStatusWithAsync(UserA, UserB);
        Assert.Equal("None", status.Status);
    }

    // ===== HAPPY PATH =====

    [Fact]
    public async Task HappyPath_SendThenAccept_BothUsersSeeEachOther()
    {
        var (sut, _) = BuildSut();

        var request = await sut.SendRequestAsync(UserA, UserB);
        Assert.Equal(ConnectionStatus.Pending, request.Status);

        // B ki incoming / A ki outgoing mein request dikhe
        var incoming = await sut.GetIncomingRequestsAsync(UserB);
        Assert.Single(incoming.Items);
        Assert.Equal(UserA, incoming.Items[0].User.UserId);

        var outgoing = await sut.GetOutgoingRequestsAsync(UserA);
        Assert.Single(outgoing.Items);
        Assert.Equal(UserB, outgoing.Items[0].User.UserId);

        await sut.AcceptRequestAsync(UserB, request.Id);

        // Dono ke connections mein ek doosra
        var aConnections = await sut.GetMyConnectionsAsync(UserA);
        Assert.Single(aConnections);
        Assert.Equal(UserB, aConnections[0].UserId);

        var bConnections = await sut.GetMyConnectionsAsync(UserB);
        Assert.Single(bConnections);
        Assert.Equal(UserA, bConnections[0].UserId);

        // Pending lists ab khali
        Assert.Empty((await sut.GetIncomingRequestsAsync(UserB)).Items);
        Assert.Empty((await sut.GetOutgoingRequestsAsync(UserA)).Items);
    }

    // ===== STATUS =====

    [Fact]
    public async Task Status_ReturnsCorrectValue_InEachState()
    {
        var (sut, _) = BuildSut();

        // No relationship
        Assert.Equal("None", (await sut.GetStatusWithAsync(UserA, UserB)).Status);

        // Pending: A → B
        var request = await sut.SendRequestAsync(UserA, UserB);
        Assert.Equal("PendingOutgoing", (await sut.GetStatusWithAsync(UserA, UserB)).Status);
        Assert.Equal("PendingIncoming", (await sut.GetStatusWithAsync(UserB, UserA)).Status);

        // Accepted
        await sut.AcceptRequestAsync(UserB, request.Id);
        Assert.Equal("Connected", (await sut.GetStatusWithAsync(UserA, UserB)).Status);
        Assert.Equal("Connected", (await sut.GetStatusWithAsync(UserB, UserA)).Status);
    }

    [Fact]
    public async Task Status_ReturnsNone_AfterRejection()
    {
        var (sut, _) = BuildSut();
        var request = await sut.SendRequestAsync(UserA, UserB);
        await sut.RejectRequestAsync(UserB, request.Id);

        Assert.Equal("None", (await sut.GetStatusWithAsync(UserA, UserB)).Status);
        Assert.Equal("None", (await sut.GetStatusWithAsync(UserB, UserA)).Status);
    }

    [Fact]
    public async Task Status_Throws400_ForSelf()
    {
        var (sut, _) = BuildSut();

        await Assert.ThrowsAsync<ValidationException>(() => sut.GetStatusWithAsync(UserA, UserA));
    }

    // ===== MUTUAL-CONNECTION CONTEXT =====

    [Fact]
    public async Task GetIncoming_ZeroMutuals_CountZeroPreviewEmpty()
    {
        var (sut, repo) = BuildMutualsSut();
        repo.All.Add(Pending(UserB, UserA));   // B requests A; no shared connections

        var result = await sut.GetIncomingRequestsAsync(UserA);

        var row = Assert.Single(result.Items);
        Assert.Equal(0, row.MutualConnectionsCount);
        Assert.NotNull(row.MutualPreview);
        Assert.Empty(row.MutualPreview);
    }

    [Fact]
    public async Task GetIncoming_TwoMutuals_CountTwoPreviewTwo()
    {
        var (sut, repo) = BuildMutualsSut();
        repo.All.Add(Pending(UserB, UserA));
        repo.All.Add(Accepted(UserA, UserM1));
        repo.All.Add(Accepted(UserA, UserM2));
        repo.All.Add(Accepted(UserB, UserM1));
        repo.All.Add(Accepted(UserB, UserM2));

        var result = await sut.GetIncomingRequestsAsync(UserA);

        var row = Assert.Single(result.Items);
        Assert.Equal(2, row.MutualConnectionsCount);
        Assert.Equal(2, row.MutualPreview.Count);
    }

    [Fact]
    public async Task GetIncoming_FiveMutuals_CountFivePreviewCappedAtThree()
    {
        var (sut, repo) = BuildMutualsSut();
        repo.All.Add(Pending(UserB, UserA));
        foreach (var m in new[] { UserM1, UserM2, UserM3, UserM4, UserM5 })
        {
            repo.All.Add(Accepted(UserA, m));
            repo.All.Add(Accepted(UserB, m));
        }

        var result = await sut.GetIncomingRequestsAsync(UserA);

        var row = Assert.Single(result.Items);
        Assert.Equal(5, row.MutualConnectionsCount);
        Assert.Equal(3, row.MutualPreview.Count);
    }

    [Fact]
    public async Task GetIncoming_PendingMutualConnection_NotCounted()
    {
        var (sut, repo) = BuildMutualsSut();
        repo.All.Add(Pending(UserB, UserA));
        repo.All.Add(Accepted(UserA, UserM1));      // Me ↔ M1: accepted
        repo.All.Add(Pending(UserM1, UserB));        // M1 → B: pending — must not count

        var result = await sut.GetIncomingRequestsAsync(UserA);

        var row = Assert.Single(result.Items);
        Assert.Equal(0, row.MutualConnectionsCount);
        Assert.Empty(row.MutualPreview);
    }

    [Fact]
    public async Task GetIncoming_RejectedMutualConnection_NotCounted()
    {
        var (sut, repo) = BuildMutualsSut();
        repo.All.Add(Pending(UserB, UserA));
        repo.All.Add(Accepted(UserA, UserM1));       // Me ↔ M1: accepted
        repo.All.Add(Rejected(UserM1, UserB));        // M1 → B: rejected — must not count

        var result = await sut.GetIncomingRequestsAsync(UserA);

        var row = Assert.Single(result.Items);
        Assert.Equal(0, row.MutualConnectionsCount);
        Assert.Empty(row.MutualPreview);
    }

    [Fact]
    public async Task GetIncoming_MeAndRequester_NeverInPreview()
    {
        var (sut, repo) = BuildMutualsSut();
        repo.All.Add(Pending(UserB, UserA));
        foreach (var m in new[] { UserM1, UserM2, UserM3 })
        {
            repo.All.Add(Accepted(UserA, m));
            repo.All.Add(Accepted(UserB, m));
        }

        var result = await sut.GetIncomingRequestsAsync(UserA);

        var row = Assert.Single(result.Items);
        var previewIds = row.MutualPreview.Select(m => m.UserId).ToHashSet();
        Assert.DoesNotContain(UserA, previewIds);   // me
        Assert.DoesNotContain(UserB, previewIds);   // requester
    }

    [Fact]
    public async Task GetIncoming_PreviewOrder_IsDeterministicAcrossCalls()
    {
        var (sut, repo) = BuildMutualsSut();
        repo.All.Add(Pending(UserB, UserA));
        foreach (var m in new[] { UserM1, UserM2, UserM3 })
        {
            repo.All.Add(Accepted(UserA, m));
            repo.All.Add(Accepted(UserB, m));
        }

        var result1 = await sut.GetIncomingRequestsAsync(UserA);
        var result2 = await sut.GetIncomingRequestsAsync(UserA);

        var ids1 = result1.Items[0].MutualPreview.Select(m => m.UserId).ToList();
        var ids2 = result2.Items[0].MutualPreview.Select(m => m.UserId).ToList();
        Assert.True(ids1.SequenceEqual(ids2), "Preview order must be identical across calls");
    }

    [Fact]
    public async Task GetIncoming_ExistingProperties_Unchanged_RegressionGuard()
    {
        var (sut, repo) = BuildMutualsSut();
        var requestTime = DateTime.UtcNow.AddMinutes(-5);
        var connectionId = Guid.NewGuid();
        repo.All.Add(new Connection
        {
            Id = connectionId, RequesterId = UserB, ReceiverId = UserA,
            Status = ConnectionStatus.Pending, CreatedAt = requestTime
        });

        var result = await sut.GetIncomingRequestsAsync(UserA);

        var row = Assert.Single(result.Items);
        Assert.Equal(connectionId, row.ConnectionId);
        Assert.Equal(UserB, row.User.UserId);
        Assert.Equal("User B", row.User.Name);
        Assert.Equal(requestTime, row.CreatedAt);
        Assert.Equal(0, row.MutualConnectionsCount);
        Assert.NotNull(row.MutualPreview);
    }

    [Fact]
    public async Task GetIncoming_TenInvitations_AllGetCorrectMutualCount()
    {
        // Bounded-query guarantee: the real repo uses a FIXED number of DB round-trips
        // (count + Q1 + Q2 + Q3) for any page size — mutual enrichment runs only over the
        // page's rows. Query-count assertions are not feasible with an in-memory fake;
        // correctness over a full 10-row page is verified here as the N4 regression guard.
        var mutualId = Guid.NewGuid();
        var tenRequesters = Enumerable.Range(0, 10).Select(_ => Guid.NewGuid()).ToArray();

        var allUsers = tenRequesters
            .Select((id, i) => new User { Id = id, FullName = $"Requester {i}" })
            .Append(new User { Id = UserA, FullName = "Me" })
            .Append(new User { Id = mutualId, FullName = "Shared Mutual" })
            .ToArray();

        var usersRepo = new InMemoryUserRepository(allUsers);
        var repo = new InMemoryConnectionRepository(usersRepo);
        var sut = new ConnectionService(repo, usersRepo, NullLogger<ConnectionService>.Instance);

        repo.All.Add(Accepted(UserA, mutualId));                // Me ↔ shared mutual
        foreach (var r in tenRequesters)
        {
            repo.All.Add(Pending(r, UserA));                    // each requests me
            repo.All.Add(Accepted(r, mutualId));                // each shares the mutual
        }

        // Request a page big enough to hold all ten (pageSize 20 > 10 rows)
        var result = await sut.GetIncomingRequestsAsync(UserA, 1, 20);

        Assert.Equal(10, result.TotalCount);
        Assert.Equal(10, result.Items.Count);
        Assert.All(result.Items, row =>
        {
            Assert.Equal(1, row.MutualConnectionsCount);
            Assert.Single(row.MutualPreview);
            Assert.Equal(mutualId, row.MutualPreview[0].UserId);
        });
    }

    // ===== PAGINATION (N5) =====

    [Fact]
    public async Task GetIncoming_PageSizeClampsTo50_Page2ReturnsNextSlice_NoRepeat()
    {
        var me = Guid.NewGuid();
        var requesters = Enumerable.Range(0, 60).Select(_ => Guid.NewGuid()).ToArray();
        var allUsers = requesters
            .Select((id, i) => new User { Id = id, FullName = $"Requester {i:D2}" })
            .Append(new User { Id = me, FullName = "Me" })
            .ToArray();

        var usersRepo = new InMemoryUserRepository(allUsers);
        var repo = new InMemoryConnectionRepository(usersRepo);
        var sut = new ConnectionService(repo, usersRepo, NullLogger<ConnectionService>.Instance);

        // 60 incoming invitations with distinct timestamps → deterministic order
        for (var i = 0; i < requesters.Length; i++)
            repo.All.Add(new Connection
            {
                Id = Guid.NewGuid(), RequesterId = requesters[i], ReceiverId = me,
                Status = ConnectionStatus.Pending, CreatedAt = DateTime.UtcNow.AddMinutes(-i)
            });

        // pageSize 1000 clamps to 50
        var page1 = await sut.GetIncomingRequestsAsync(me, 1, 1000);
        Assert.Equal(50, page1.PageSize);
        Assert.Equal(50, page1.Items.Count);
        Assert.Equal(60, page1.TotalCount);
        Assert.True(page1.HasNextPage);

        var page2 = await sut.GetIncomingRequestsAsync(me, 2, ConnectionService.MaxPageSize);
        Assert.Equal(10, page2.Items.Count);
        Assert.Equal(60, page2.TotalCount);
        Assert.False(page2.HasNextPage);

        // No row repeats across pages
        var page1Ids = page1.Items.Select(x => x.ConnectionId).ToHashSet();
        Assert.All(page2.Items, x => Assert.DoesNotContain(x.ConnectionId, page1Ids));
    }

    [Fact]
    public async Task GetOutgoing_PageSizeClampsTo50_Page2ReturnsNextSlice_NoRepeat()
    {
        var me = Guid.NewGuid();
        var receivers = Enumerable.Range(0, 60).Select(_ => Guid.NewGuid()).ToArray();
        var allUsers = receivers
            .Select((id, i) => new User { Id = id, FullName = $"Receiver {i:D2}" })
            .Append(new User { Id = me, FullName = "Me" })
            .ToArray();

        var usersRepo = new InMemoryUserRepository(allUsers);
        var repo = new InMemoryConnectionRepository(usersRepo);
        var sut = new ConnectionService(repo, usersRepo, NullLogger<ConnectionService>.Instance);

        for (var i = 0; i < receivers.Length; i++)
            repo.All.Add(new Connection
            {
                Id = Guid.NewGuid(), RequesterId = me, ReceiverId = receivers[i],
                Status = ConnectionStatus.Pending, CreatedAt = DateTime.UtcNow.AddMinutes(-i)
            });

        var page1 = await sut.GetOutgoingRequestsAsync(me, 1, 1000);
        Assert.Equal(50, page1.PageSize);
        Assert.Equal(50, page1.Items.Count);
        Assert.Equal(60, page1.TotalCount);
        Assert.True(page1.HasNextPage);

        var page2 = await sut.GetOutgoingRequestsAsync(me, 2, ConnectionService.MaxPageSize);
        Assert.Equal(10, page2.Items.Count);
        Assert.Equal(60, page2.TotalCount);
        Assert.False(page2.HasNextPage);

        var page1Ids = page1.Items.Select(x => x.ConnectionId).ToHashSet();
        Assert.All(page2.Items, x => Assert.DoesNotContain(x.ConnectionId, page1Ids));
    }

    [Fact]
    public async Task GetIncoming_EmptyResult_ReturnsValidEmptyPagedResult()
    {
        var (sut, _) = BuildSut();   // no invitations seeded

        var result = await sut.GetIncomingRequestsAsync(UserA);

        Assert.NotNull(result);
        Assert.Empty(result.Items);
        Assert.Equal(0, result.TotalCount);
        Assert.False(result.HasNextPage);
    }

    [Fact]
    public async Task GetOutgoing_EmptyResult_ReturnsValidEmptyPagedResult()
    {
        var (sut, _) = BuildSut();   // no invitations seeded

        var result = await sut.GetOutgoingRequestsAsync(UserA);

        Assert.NotNull(result);
        Assert.Empty(result.Items);
        Assert.Equal(0, result.TotalCount);
        Assert.False(result.HasNextPage);
    }

    [Fact]
    public async Task GetIncoming_Ordering_IsDeterministicAcrossIdenticalCalls()
    {
        var me = Guid.NewGuid();
        var requesters = Enumerable.Range(0, 15).Select(_ => Guid.NewGuid()).ToArray();
        var allUsers = requesters
            .Select((id, i) => new User { Id = id, FullName = $"Requester {i:D2}" })
            .Append(new User { Id = me, FullName = "Me" })
            .ToArray();

        var usersRepo = new InMemoryUserRepository(allUsers);
        var repo = new InMemoryConnectionRepository(usersRepo);
        var sut = new ConnectionService(repo, usersRepo, NullLogger<ConnectionService>.Instance);

        // Half the rows share the SAME timestamp → forces the Id tiebreaker to decide order
        var shared = DateTime.UtcNow.AddMinutes(-5);
        for (var i = 0; i < requesters.Length; i++)
            repo.All.Add(new Connection
            {
                Id = Guid.NewGuid(), RequesterId = requesters[i], ReceiverId = me,
                Status = ConnectionStatus.Pending,
                CreatedAt = i % 2 == 0 ? shared : DateTime.UtcNow.AddMinutes(-i)
            });

        var first = await sut.GetIncomingRequestsAsync(me, 1, 10);
        var second = await sut.GetIncomingRequestsAsync(me, 1, 10);

        Assert.Equal(
            first.Items.Select(x => x.ConnectionId),
            second.Items.Select(x => x.ConnectionId));
    }

    // ===== INVITE POLICY ENFORCEMENT (N7) =====

    [Fact]
    public async Task Send_NullPolicy_AllowsRequest()
    {
        var (sut, repo) = BuildSut();
        // No policy seeded → GetReceiverPolicyAsync returns null → Everyone semantics

        var result = await sut.SendRequestAsync(UserA, UserB);

        Assert.Equal(ConnectionStatus.Pending, result.Status);
        Assert.Single(repo.All);
    }

    [Fact]
    public async Task Send_EveryonePolicy_AllowsRequest()
    {
        var (sut, repo) = BuildSut();
        repo.SeedPolicy(UserB, ConnectionInvitePolicy.Everyone);

        var result = await sut.SendRequestAsync(UserA, UserB);

        Assert.Equal(ConnectionStatus.Pending, result.Status);
        Assert.Single(repo.All);
    }

    [Fact]
    public async Task Send_NoOnePolicy_Throws403_NoPendingRowCreated()
    {
        var (sut, repo) = BuildSut();
        repo.SeedPolicy(UserB, ConnectionInvitePolicy.NoOne);

        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.SendRequestAsync(UserA, UserB));

        Assert.Equal(403, ex.StatusCode);
        Assert.Empty(repo.All);
    }

    [Fact]
    public async Task Send_MutualsOnly_WithSharedAcceptedMutual_AllowsRequest()
    {
        var (sut, repo) = BuildMutualsSut();
        repo.SeedPolicy(UserB, ConnectionInvitePolicy.MutualsOnly);
        // UserA ↔ UserM1 accepted, UserB ↔ UserM1 accepted → shared mutual
        repo.All.Add(Accepted(UserA, UserM1));
        repo.All.Add(Accepted(UserB, UserM1));

        var result = await sut.SendRequestAsync(UserA, UserB);

        Assert.Equal(ConnectionStatus.Pending, result.Status);
    }

    [Fact]
    public async Task Send_MutualsOnly_WithNoSharedMutual_Throws403_NoPendingRowCreated()
    {
        var (sut, repo) = BuildSut();
        repo.SeedPolicy(UserB, ConnectionInvitePolicy.MutualsOnly);
        // No shared connections

        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.SendRequestAsync(UserA, UserB));

        Assert.Equal(403, ex.StatusCode);
        Assert.Empty(repo.All);
    }

    [Fact]
    public async Task Send_MutualsOnly_PendingOrRejectedMutualLink_NotCountedAsMutual()
    {
        var (sut, repo) = BuildMutualsSut();
        repo.SeedPolicy(UserB, ConnectionInvitePolicy.MutualsOnly);
        // A ↔ M1 accepted, but M1 → B is Pending (not Accepted) → not a real mutual
        repo.All.Add(Accepted(UserA, UserM1));
        repo.All.Add(Pending(UserM1, UserB));
        // A ↔ M2 accepted, but M2 → B is Rejected → not a real mutual
        repo.All.Add(Accepted(UserA, UserM2));
        repo.All.Add(Rejected(UserM2, UserB));

        var ex = await Assert.ThrowsAsync<ForbiddenException>(
            () => sut.SendRequestAsync(UserA, UserB));

        Assert.Equal(403, ex.StatusCode);
    }

    [Fact]
    public async Task Send_PolicyCheck_DoesNotBreak_ExistingValidationRules()
    {
        var (sut, repo) = BuildSut();
        repo.SeedPolicy(UserB, ConnectionInvitePolicy.Everyone);

        // Self-request still 400 even with Everyone policy on B
        var selfEx = await Assert.ThrowsAsync<ValidationException>(
            () => sut.SendRequestAsync(UserA, UserA));
        Assert.Equal(400, selfEx.StatusCode);

        // First request succeeds
        await sut.SendRequestAsync(UserA, UserB);

        // Duplicate still 409 — policy doesn't bypass the duplicate guard
        var dupEx = await Assert.ThrowsAsync<ConflictException>(
            () => sut.SendRequestAsync(UserA, UserB));
        Assert.Equal(409, dupEx.StatusCode);
    }

    // ===== Test doubles =====

    private sealed class InMemoryUserRepository(params User[] users) : IUserRepository
    {
        public readonly List<User> Users = [.. users];

        public Task<User?> GetByIdAsync(Guid id) =>
            Task.FromResult(Users.FirstOrDefault(u => u.Id == id));

        public Task<User?> GetByEmailAsync(string email) => Task.FromResult<User?>(null);
        public Task<User?> GetByExternalIdAsync(AuthProvider provider, string externalId) => Task.FromResult<User?>(null);
        public Task<bool> EmailExistsAsync(string email) => Task.FromResult(false);
        public Task AddAsync(User user) { Users.Add(user); return Task.CompletedTask; }
        public Task SaveChangesAsync() => Task.CompletedTask;
        public Task<Guid?> GetSecurityStampAsync(Guid userId) => Task.FromResult<Guid?>(null);
    }

    private sealed class InMemoryConnectionRepository(InMemoryUserRepository users) : IConnectionRepository
    {
        public readonly List<Connection> All = [];
        private readonly List<Connection> _pendingAdds = [];
        private readonly List<Connection> _pendingRemoves = [];
        private readonly Dictionary<Guid, ConnectionInvitePolicy?> _policies = [];

        public Task<Connection?> GetByIdAsync(Guid id) =>
            Task.FromResult(All.FirstOrDefault(c => c.Id == id));

        public Task<List<Connection>> GetBetweenUsersAsync(Guid a, Guid b) =>
            Task.FromResult(All
                .Where(c => (c.RequesterId == a && c.ReceiverId == b) ||
                            (c.RequesterId == b && c.ReceiverId == a))
                .ToList());

        public Task AddAsync(Connection connection) { _pendingAdds.Add(connection); return Task.CompletedTask; }
        public void Remove(Connection connection) => _pendingRemoves.Add(connection);

        public Task<List<ConnectionUserDto>> GetAcceptedUsersAsync(Guid userId) =>
            Task.FromResult(All
                .Where(c => c.Status == ConnectionStatus.Accepted &&
                            (c.RequesterId == userId || c.ReceiverId == userId))
                .Select(c => ToUserDto(c.RequesterId == userId ? c.ReceiverId : c.RequesterId))
                .ToList());

        public Task<PagedResult<PendingRequestDto>> GetPendingIncomingWithMutualsAsync(
            Guid meId, int page, int pageSize, CancellationToken ct)
        {
            // My accepted counterpart IDs (mirrors Q1 in the real repo)
            var myAcceptedIds = All
                .Where(c => c.Status == ConnectionStatus.Accepted &&
                           (c.RequesterId == meId || c.ReceiverId == meId))
                .Select(c => c.RequesterId == meId ? c.ReceiverId : c.RequesterId)
                .ToHashSet();

            // Stable order (newest first, Id tiebreaker), then page — mirrors the real repo.
            var ordered = All
                .Where(c => c.Status == ConnectionStatus.Pending && c.ReceiverId == meId)
                .OrderByDescending(c => c.CreatedAt)
                .ThenBy(c => c.Id)
                .ToList();

            var totalCount = ordered.Count;

            // Enrichment runs ONLY over the current page's rows.
            var items = ordered
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(inv =>
                {
                    // Requester's accepted counterpart IDs (mirrors Q3 intersection in the real repo).
                    // N+1 in-memory is acceptable for tests; real repo uses a bounded single query.
                    var requesterAcceptedIds = All
                        .Where(c => c.Status == ConnectionStatus.Accepted &&
                                   (c.RequesterId == inv.RequesterId || c.ReceiverId == inv.RequesterId))
                        .Select(c => c.RequesterId == inv.RequesterId ? c.ReceiverId : c.RequesterId)
                        .ToHashSet();

                    var mutuals = myAcceptedIds
                        .Intersect(requesterAcceptedIds)
                        .Select(id => new { Id = id, Name = users.Users.FirstOrDefault(u => u.Id == id)?.FullName ?? string.Empty })
                        .OrderBy(m => m.Name)
                        .ThenBy(m => m.Id)
                        .ToList();

                    return new PendingRequestDto
                    {
                        ConnectionId = inv.Id,
                        CreatedAt = inv.CreatedAt,
                        User = ToUserDto(inv.RequesterId),
                        MutualConnectionsCount = mutuals.Count,
                        MutualPreview = mutuals
                            .Take(3)
                            .Select(m => new MutualPreview { UserId = m.Id, FullName = m.Name })
                            .ToList()
                    };
                })
                .ToList();

            return Task.FromResult(new PagedResult<PendingRequestDto>
            {
                Items = items,
                Page = page,
                PageSize = pageSize,
                TotalCount = totalCount
            });
        }

        public Task<PagedResult<PendingRequestDto>> GetPendingOutgoingAsync(
            Guid userId, int page, int pageSize, CancellationToken ct)
        {
            var ordered = All
                .Where(c => c.Status == ConnectionStatus.Pending && c.RequesterId == userId)
                .OrderByDescending(c => c.CreatedAt)
                .ThenBy(c => c.Id)
                .ToList();

            var totalCount = ordered.Count;

            var items = ordered
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(c => new PendingRequestDto
                {
                    ConnectionId = c.Id,
                    CreatedAt = c.CreatedAt,
                    User = ToUserDto(c.ReceiverId)
                })
                .ToList();

            return Task.FromResult(new PagedResult<PendingRequestDto>
            {
                Items = items,
                Page = page,
                PageSize = pageSize,
                TotalCount = totalCount
            });
        }

        public void SeedPolicy(Guid userId, ConnectionInvitePolicy? policy) => _policies[userId] = policy;

        public Task<ConnectionInvitePolicy?> GetReceiverPolicyAsync(Guid receiverId, CancellationToken ct)
            => Task.FromResult(_policies.GetValueOrDefault(receiverId, null));

        public Task<bool> ShareMutualConnectionAsync(Guid userA, Guid userB, CancellationToken ct)
        {
            var aPartners = All
                .Where(c => c.Status == ConnectionStatus.Accepted &&
                            (c.RequesterId == userA || c.ReceiverId == userA))
                .Select(c => c.RequesterId == userA ? c.ReceiverId : c.RequesterId)
                .ToHashSet();

            var bPartners = All
                .Where(c => c.Status == ConnectionStatus.Accepted &&
                            (c.RequesterId == userB || c.ReceiverId == userB))
                .Select(c => c.RequesterId == userB ? c.ReceiverId : c.RequesterId)
                .ToHashSet();

            return Task.FromResult(aPartners.Overlaps(bPartners));
        }

        public Task<(int Connections, int InvitesSent, int InvitesReceived)> GetCountsAsync(Guid userId, CancellationToken ct)
        {
            var connections = All.Count(c => c.Status == ConnectionStatus.Accepted && (c.RequesterId == userId || c.ReceiverId == userId));
            var invitesSent = All.Count(c => c.Status == ConnectionStatus.Pending && c.RequesterId == userId);
            var invitesReceived = All.Count(c => c.Status == ConnectionStatus.Pending && c.ReceiverId == userId);
            return Task.FromResult((connections, invitesSent, invitesReceived));
        }

        public Task SaveChangesAsync()
        {
            // DB ki unique (RequesterId, ReceiverId) constraint ka simulation
            foreach (var add in _pendingAdds)
            {
                if (All.Any(c => c.RequesterId == add.RequesterId && c.ReceiverId == add.ReceiverId))
                    throw new ConflictException("A connection request between these users already exists.");
                All.Add(add);
            }
            _pendingAdds.Clear();

            foreach (var remove in _pendingRemoves)
                All.Remove(remove);
            _pendingRemoves.Clear();

            return Task.CompletedTask;
        }

        private ConnectionUserDto ToUserDto(Guid userId) => new()
        {
            UserId = userId,
            Name = users.Users.FirstOrDefault(u => u.Id == userId)?.FullName ?? string.Empty
        };
    }
}
