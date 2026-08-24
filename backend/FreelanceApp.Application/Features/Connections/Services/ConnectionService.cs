using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Connections.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging;

namespace FreelanceApp.Application.Features.Connections.Services;

public class ConnectionService(
    IConnectionRepository connectionRepository,
    IUserRepository userRepository,
    ILogger<ConnectionService> logger) : IConnectionService
{
    // ===== SEND =====

    public async Task<ConnectionRequestResponseDto> SendRequestAsync(
        Guid userId, Guid receiverId, CancellationToken ct = default)
    {
        if (receiverId == userId)
            throw new ValidationException("You cannot send a connection request to yourself.");

        var receiver = await userRepository.GetByIdAsync(receiverId)
            ?? throw new NotFoundException("User not found.");

        // Dono directions ki existing rows check — Accepted ya Pending ho to block
        var existing = await connectionRepository.GetBetweenUsersAsync(userId, receiverId);

        if (existing.Any(c => c.Status == ConnectionStatus.Accepted))
            throw new ConflictException("You are already connected with this user.");

        var pending = existing.FirstOrDefault(c => c.Status == ConnectionStatus.Pending);
        if (pending != null)
        {
            throw pending.RequesterId == userId
                ? new ConflictException("You have already sent a connection request to this user.")
                : new ConflictException(
                    "This user has already sent you a connection request — accept it instead.");
        }

        // ── Policy enforcement (after self/duplicate/connected checks, before write) ──
        // Order rationale: self (400) and duplicate (409) are cheaper and unambiguous —
        // they fire regardless of policy. Policy (403) runs only when the request would
        // otherwise be a valid new submission, keeping error semantics clean.
        var policy = await connectionRepository.GetReceiverPolicyAsync(receiver.Id, ct);
        if (policy == ConnectionInvitePolicy.NoOne)
            throw new ForbiddenException("This user isn't accepting new connection requests.");

        if (policy == ConnectionInvitePolicy.MutualsOnly)
        {
            var sharesMutual = await connectionRepository.ShareMutualConnectionAsync(userId, receiver.Id, ct);
            if (!sharesMutual)
                throw new ForbiddenException("This user only accepts requests from people they share a connection with.");
        }

        // Meri direction mein purani Rejected row ho to usi ko dobara Pending banate
        // hain — unique (RequesterId, ReceiverId) index nayi row allow nahi karta.
        var connection = existing.FirstOrDefault(
            c => c.RequesterId == userId && c.Status == ConnectionStatus.Rejected);

        if (connection != null)
        {
            connection.Status = ConnectionStatus.Pending;
            connection.CreatedAt = DateTime.UtcNow;
            connection.RespondedAt = null;
        }
        else
        {
            connection = new Connection
            {
                Id = Guid.NewGuid(),
                RequesterId = userId,
                ReceiverId = receiver.Id,
                Status = ConnectionStatus.Pending,
                CreatedAt = DateTime.UtcNow
            };
            await connectionRepository.AddAsync(connection);
        }

        await connectionRepository.SaveChangesAsync();

        logger.LogInformation(
            "Connection request sent | Requester: {RequesterId} | Receiver: {ReceiverId}", userId, receiverId);

        return MapToDto(connection);
    }

    // ===== ACCEPT / REJECT =====

    public Task AcceptRequestAsync(Guid userId, Guid connectionId, CancellationToken ct = default)
        => RespondAsync(userId, connectionId, ConnectionStatus.Accepted);

    public Task RejectRequestAsync(Guid userId, Guid connectionId, CancellationToken ct = default)
        => RespondAsync(userId, connectionId, ConnectionStatus.Rejected);

    private async Task RespondAsync(Guid userId, Guid connectionId, ConnectionStatus newStatus)
    {
        var connection = await connectionRepository.GetByIdAsync(connectionId)
            ?? throw new NotFoundException("Connection request not found.");

        // Sirf receiver respond kar sakta hai
        if (connection.ReceiverId != userId)
            throw new ForbiddenException("Only the receiver of this request can respond to it.");

        if (connection.Status != ConnectionStatus.Pending)
            throw new ConflictException("This request has already been responded to.");

        connection.Status = newStatus;
        connection.RespondedAt = DateTime.UtcNow;
        await connectionRepository.SaveChangesAsync();

        logger.LogInformation(
            "Connection request {Status} | Connection: {ConnectionId} | Receiver: {UserId}",
            newStatus, connectionId, userId);
    }

    // ===== WITHDRAW =====

    public async Task WithdrawRequestAsync(Guid userId, Guid connectionId, CancellationToken ct = default)
    {
        var connection = await connectionRepository.GetByIdAsync(connectionId)
            ?? throw new NotFoundException("Connection request not found.");

        // Sirf requester apni request withdraw kar sakta hai
        if (connection.RequesterId != userId)
            throw new ForbiddenException("Only the requester can withdraw this request.");

        if (connection.Status != ConnectionStatus.Pending)
            throw new ConflictException("Only a pending request can be withdrawn.");

        connectionRepository.Remove(connection);
        await connectionRepository.SaveChangesAsync();

        logger.LogInformation(
            "Connection request withdrawn | Connection: {ConnectionId} | Requester: {UserId}",
            connectionId, userId);
    }

    // ===== LISTS =====

    // Paging clamp — same behavior as PeopleService (page >= 1, pageSize 1..50).
    public const int DefaultPageSize = 20;
    public const int MaxPageSize = 50;

    public Task<List<ConnectionUserDto>> GetMyConnectionsAsync(Guid userId, CancellationToken ct = default)
        => connectionRepository.GetAcceptedUsersAsync(userId);

    public Task<PagedResult<PendingRequestDto>> GetIncomingRequestsAsync(
        Guid userId, int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        var (p, ps) = ClampPaging(page, pageSize);
        return connectionRepository.GetPendingIncomingWithMutualsAsync(userId, p, ps, ct);
    }

    public Task<PagedResult<PendingRequestDto>> GetOutgoingRequestsAsync(
        Guid userId, int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        var (p, ps) = ClampPaging(page, pageSize);
        return connectionRepository.GetPendingOutgoingAsync(userId, p, ps, ct);
    }

    // Clamp (not reject): koi poori table na kheench sake. Mirrors PeopleService.
    private static (int page, int pageSize) ClampPaging(int page, int pageSize)
    {
        var p = page < 1 ? 1 : page;
        var ps = pageSize < 1 ? DefaultPageSize
               : pageSize > MaxPageSize ? MaxPageSize
               : pageSize;
        return (p, ps);
    }

    // ===== STATUS =====

    public async Task<ConnectionStatusResponseDto> GetStatusWithAsync(
        Guid userId, Guid otherUserId, CancellationToken ct = default)
    {
        if (otherUserId == userId)
            throw new ValidationException("Cannot check connection status with yourself.");

        var rows = await connectionRepository.GetBetweenUsersAsync(userId, otherUserId);

        string status;
        if (rows.Any(c => c.Status == ConnectionStatus.Accepted))
            status = "Connected";
        else if (rows.Any(c => c.Status == ConnectionStatus.Pending && c.RequesterId == userId))
            status = "PendingOutgoing";
        else if (rows.Any(c => c.Status == ConnectionStatus.Pending && c.ReceiverId == userId))
            status = "PendingIncoming";
        else
            status = "None";   // koi row nahi, ya sirf Rejected — dobara request ho sakti hai

        return new ConnectionStatusResponseDto { Status = status };
    }

    // ===== HELPERS =====

    private static ConnectionRequestResponseDto MapToDto(Connection c) => new()
    {
        Id = c.Id,
        RequesterId = c.RequesterId,
        ReceiverId = c.ReceiverId,
        Status = c.Status,
        CreatedAt = c.CreatedAt,
        RespondedAt = c.RespondedAt
    };
}
