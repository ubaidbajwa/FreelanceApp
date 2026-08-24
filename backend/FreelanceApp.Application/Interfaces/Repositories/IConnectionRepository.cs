using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Connections.DTOs;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface IConnectionRepository
{
    Task<Connection?> GetByIdAsync(Guid id);

    // Dono directions (A→B aur B→A) ki rows — max 2 ho sakti hain
    Task<List<Connection>> GetBetweenUsersAsync(Guid userIdA, Guid userIdB);

    Task AddAsync(Connection connection);
    void Remove(Connection connection);

    // Read models — counterpart user (name/headline/photo) DB mein hi project hota hai
    Task<List<ConnectionUserDto>> GetAcceptedUsersAsync(Guid userId);

    /// <summary>
    /// One page of outgoing pending invitations (newest first, Id tiebreaker for stable paging).
    /// </summary>
    Task<PagedResult<PendingRequestDto>> GetPendingOutgoingAsync(
        Guid userId, int page, int pageSize, CancellationToken ct);

    /// <summary>
    /// One page of incoming pending invitations, each enriched with mutual-connection context
    /// using a BOUNDED set of queries (count + Q1 + Q2 + Q3). The number of DB round trips does
    /// NOT grow with the page size; mutual enrichment runs only over the current page's rows.
    /// </summary>
    Task<PagedResult<PendingRequestDto>> GetPendingIncomingWithMutualsAsync(
        Guid meId, int page, int pageSize, CancellationToken ct);

    // Single-query aggregate counts for the network overview
    Task<(int Connections, int InvitesSent, int InvitesReceived)> GetCountsAsync(Guid userId, CancellationToken ct);

    /// <summary>
    /// Returns the receiver's ConnectionInvitePolicy (null = Everyone / open default).
    /// Single-field projection — no profile load overhead on the critical send-request path.
    /// </summary>
    Task<ConnectionInvitePolicy?> GetReceiverPolicyAsync(Guid receiverId, CancellationToken ct);

    /// <summary>
    /// Returns true if userA and userB share at least one accepted mutual connection.
    /// Single bounded query (INTERSECT) — not a per-row N+1.
    /// </summary>
    Task<bool> ShareMutualConnectionAsync(Guid userA, Guid userB, CancellationToken ct);

    Task SaveChangesAsync();
}
