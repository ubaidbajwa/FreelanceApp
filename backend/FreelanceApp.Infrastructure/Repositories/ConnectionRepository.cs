using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Connections.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace FreelanceApp.Infrastructure.Repositories;

public class ConnectionRepository : IConnectionRepository
{
    private readonly AppDbContext _context;

    public ConnectionRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Connection?> GetByIdAsync(Guid id)
    {
        return await _context.Connections.FirstOrDefaultAsync(c => c.Id == id);
    }

    public async Task<List<Connection>> GetBetweenUsersAsync(Guid userIdA, Guid userIdB)
    {
        return await _context.Connections
            .Where(c => (c.RequesterId == userIdA && c.ReceiverId == userIdB) ||
                        (c.RequesterId == userIdB && c.ReceiverId == userIdA))
            .ToListAsync();
    }

    public async Task AddAsync(Connection connection)
    {
        await _context.Connections.AddAsync(connection);
    }

    public void Remove(Connection connection)
    {
        _context.Connections.Remove(connection);
    }

    // ===== READ MODELS =====
    // Counterpart user + (optional) profile DB mein hi project hota hai — no N+1.
    // Profile left-joined: naya user jiska profile abhi nahi bana, wo bhi dikhe.

    public async Task<List<ConnectionUserDto>> GetAcceptedUsersAsync(Guid userId)
    {
        return await _context.Connections
            .Where(c => c.Status == ConnectionStatus.Accepted &&
                        (c.RequesterId == userId || c.ReceiverId == userId))
            .Select(c => c.RequesterId == userId ? c.ReceiverId : c.RequesterId)
            .Join(_context.Users, otherId => otherId, u => u.Id, (otherId, u) => u)
            .Select(u => new ConnectionUserDto
            {
                UserId = u.Id,
                Name = u.FullName,
                Headline = _context.Profiles
                    .Where(p => p.UserId == u.Id).Select(p => p.Headline).FirstOrDefault(),
                ProfilePhotoUrl = _context.Profiles
                    .Where(p => p.UserId == u.Id).Select(p => p.ProfilePhotoUrl).FirstOrDefault()
            })
            .ToListAsync();
    }

    public async Task<PagedResult<PendingRequestDto>> GetPendingOutgoingAsync(
        Guid userId, int page, int pageSize, CancellationToken ct)
    {
        // Two round trips: total count + one page. No enrichment needed for outgoing.
        var baseQuery = _context.Connections
            .AsNoTracking()
            .Where(c => c.Status == ConnectionStatus.Pending && c.RequesterId == userId);

        var totalCount = await baseQuery.CountAsync(ct);

        // Stable order: newest first, then Id — pagination can't repeat or skip rows.
        var items = await baseQuery
            .OrderByDescending(c => c.CreatedAt)
            .ThenBy(c => c.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(c => new PendingRequestDto
            {
                ConnectionId = c.Id,
                CreatedAt = c.CreatedAt,
                User = new ConnectionUserDto
                {
                    UserId = c.ReceiverId,
                    Name = _context.Users
                        .Where(u => u.Id == c.ReceiverId).Select(u => u.FullName).First(),
                    Headline = _context.Profiles
                        .Where(p => p.UserId == c.ReceiverId).Select(p => p.Headline).FirstOrDefault(),
                    ProfilePhotoUrl = _context.Profiles
                        .Where(p => p.UserId == c.ReceiverId).Select(p => p.ProfilePhotoUrl).FirstOrDefault()
                }
            })
            .ToListAsync(ct);

        return new PagedResult<PendingRequestDto>
        {
            Items = items,
            Page = page,
            PageSize = pageSize,
            TotalCount = totalCount
        };
    }

    public async Task<PagedResult<PendingRequestDto>> GetPendingIncomingWithMutualsAsync(
        Guid meId, int page, int pageSize, CancellationToken ct)
    {
        // Bounded-query guarantee: a FIXED number of DB round-trips regardless of page size.
        // Q0 count → Q1 my-connections → Q2 this-page invitations → Q3 mutuals (conditional).
        // Mutual enrichment (Q3) runs ONLY over the current page's requester IDs.

        var baseQuery = _context.Connections
            .AsNoTracking()
            .Where(c => c.Status == ConnectionStatus.Pending && c.ReceiverId == meId);

        // Q0 — total pending incoming, for the pagination envelope
        var totalCount = await baseQuery.CountAsync(ct);

        // Q1 — my accepted connection counterpart IDs (ids only, narrow)
        var myConnectionIds = await _context.Connections
            .AsNoTracking()
            .Where(c => c.Status == ConnectionStatus.Accepted &&
                       (c.RequesterId == meId || c.ReceiverId == meId))
            .Select(c => c.RequesterId == meId ? c.ReceiverId : c.RequesterId)
            .ToListAsync(ct);

        // Q2 — THIS PAGE of incoming pending invitations with requester details.
        // Stable order: newest first, then Id — pagination can't repeat or skip rows.
        var rawInvitations = await baseQuery
            .OrderByDescending(c => c.CreatedAt)
            .ThenBy(c => c.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(c => new
            {
                c.Id,
                c.CreatedAt,
                c.RequesterId,
                RequesterName = _context.Users
                    .Where(u => u.Id == c.RequesterId).Select(u => u.FullName).First(),
                RequesterHeadline = _context.Profiles
                    .Where(p => p.UserId == c.RequesterId).Select(p => p.Headline).FirstOrDefault(),
                RequesterPhotoUrl = _context.Profiles
                    .Where(p => p.UserId == c.RequesterId).Select(p => p.ProfilePhotoUrl).FirstOrDefault()
            })
            .ToListAsync(ct);

        if (rawInvitations.Count == 0)
            return new PagedResult<PendingRequestDto>
            {
                Items = [],
                Page = page,
                PageSize = pageSize,
                TotalCount = totalCount
            };

        var myConnectionIdSet = myConnectionIds.ToHashSet();
        var requesterIds = rawInvitations.Select(i => i.RequesterId).Distinct().ToList();

        // Q3 — ONE query for all mutual-connection rows across the entire page.
        // Mutual = user M who has Accepted connection with me AND Accepted connection with requester R.
        // Two halves (different direction of the M-R connection) are combined with Union (UNION in SQL).
        // Guard: skip Q3 when myConnectionIds is empty — no mutuals possible, saves a round-trip.
        //
        // Same intersection concept as SuggestionService mutual counting;
        // not extracted to a shared helper to avoid coupling Connections ↔ Network domains.
        List<MutualRawRow> mutualRows = [];
        if (myConnectionIdSet.Count > 0)
        {
            var myIdList = myConnectionIdSet.ToList();

            // Half A: mutual M is the RequesterId; page-requester R is the ReceiverId
            var halfA =
                from c in _context.Connections
                where c.Status == ConnectionStatus.Accepted
                   && myIdList.Contains(c.RequesterId)
                   && requesterIds.Contains(c.ReceiverId)
                join u in _context.Users on c.RequesterId equals u.Id
                join p in _context.Profiles on u.Id equals p.UserId into pg
                from p in pg.DefaultIfEmpty()
                select new MutualRawRow
                {
                    RequesterOnPageId = c.ReceiverId,
                    MutualId = c.RequesterId,
                    MutualFullName = u.FullName,
                    MutualPhotoUrl = p != null ? p.ProfilePhotoUrl : null
                };

            // Half B: mutual M is the ReceiverId; page-requester R is the RequesterId
            var halfB =
                from c in _context.Connections
                where c.Status == ConnectionStatus.Accepted
                   && requesterIds.Contains(c.RequesterId)
                   && myIdList.Contains(c.ReceiverId)
                join u in _context.Users on c.ReceiverId equals u.Id
                join p in _context.Profiles on u.Id equals p.UserId into pg
                from p in pg.DefaultIfEmpty()
                select new MutualRawRow
                {
                    RequesterOnPageId = c.RequesterId,
                    MutualId = c.ReceiverId,
                    MutualFullName = u.FullName,
                    MutualPhotoUrl = p != null ? p.ProfilePhotoUrl : null
                };

            mutualRows = await halfA.Union(halfB).AsNoTracking().ToListAsync(ct);
        }

        // Group by requester in memory — no more DB calls
        var mutualsByRequester = mutualRows
            .GroupBy(r => r.RequesterOnPageId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var items = rawInvitations.Select(inv =>
        {
            var mutuals = mutualsByRequester.GetValueOrDefault(inv.RequesterId, [])
                .OrderBy(m => m.MutualFullName)
                .ThenBy(m => m.MutualId)
                .ToList();

            return new PendingRequestDto
            {
                ConnectionId = inv.Id,
                CreatedAt = inv.CreatedAt,
                User = new ConnectionUserDto
                {
                    UserId = inv.RequesterId,
                    Name = inv.RequesterName,
                    Headline = inv.RequesterHeadline,
                    ProfilePhotoUrl = inv.RequesterPhotoUrl
                },
                MutualConnectionsCount = mutuals.Count,
                MutualPreview = mutuals
                    .Take(3)
                    .Select(m => new MutualPreview
                    {
                        UserId = m.MutualId,
                        FullName = m.MutualFullName,
                        PhotoUrl = m.MutualPhotoUrl
                    })
                    .ToList()
            };
        }).ToList();

        return new PagedResult<PendingRequestDto>
        {
            Items = items,
            Page = page,
            PageSize = pageSize,
            TotalCount = totalCount
        };
    }

    // Private projection type for the mutual-connection Q3 query
    private sealed class MutualRawRow
    {
        public Guid RequesterOnPageId { get; set; }
        public Guid MutualId { get; set; }
        public string MutualFullName { get; set; } = string.Empty;
        public string? MutualPhotoUrl { get; set; }
    }

    public async Task<ConnectionInvitePolicy?> GetReceiverPolicyAsync(Guid receiverId, CancellationToken ct)
    {
        // Projects a single nullable int column — no full profile load.
        // null returned when receiver has no profile (treated as Everyone by the service).
        return await _context.Profiles
            .AsNoTracking()
            .Where(p => p.UserId == receiverId)
            .Select(p => p.InvitePolicy)
            .FirstOrDefaultAsync(ct);
    }

    public async Task<bool> ShareMutualConnectionAsync(Guid userA, Guid userB, CancellationToken ct)
    {
        // Build the two sets as subqueries — EF translates to INTERSECT in SQL:
        //   SELECT partner_id FROM accepted connections of A
        //   INTERSECT
        //   SELECT partner_id FROM accepted connections of B
        // One bounded query regardless of connection counts; no N+1.

        var aPartners =
            _context.Connections
                .Where(c => c.Status == ConnectionStatus.Accepted && c.RequesterId == userA)
                .Select(c => c.ReceiverId)
            .Union(
            _context.Connections
                .Where(c => c.Status == ConnectionStatus.Accepted && c.ReceiverId == userA)
                .Select(c => c.RequesterId));

        var bPartners =
            _context.Connections
                .Where(c => c.Status == ConnectionStatus.Accepted && c.RequesterId == userB)
                .Select(c => c.ReceiverId)
            .Union(
            _context.Connections
                .Where(c => c.Status == ConnectionStatus.Accepted && c.ReceiverId == userB)
                .Select(c => c.RequesterId));

        return await aPartners.Intersect(bPartners).AnyAsync(ct);
    }

    public async Task<(int Connections, int InvitesSent, int InvitesReceived)> GetCountsAsync(
        Guid userId, CancellationToken ct)
    {
        var counts = await _context.Connections
            .AsNoTracking()
            .Where(c => c.RequesterId == userId || c.ReceiverId == userId)
            .GroupBy(_ => 0)
            .Select(g => new
            {
                Connections = g.Count(c => c.Status == ConnectionStatus.Accepted),
                InvitesSent = g.Count(c => c.Status == ConnectionStatus.Pending && c.RequesterId == userId),
                InvitesReceived = g.Count(c => c.Status == ConnectionStatus.Pending && c.ReceiverId == userId)
            })
            .FirstOrDefaultAsync(ct);

        return counts is null ? (0, 0, 0) : (counts.Connections, counts.InvitesSent, counts.InvitesReceived);
    }

    public async Task SaveChangesAsync()
    {
        try
        {
            await _context.SaveChangesAsync();
        }
        // Race: service ke duplicate-check ke baad, save se pehle, wahi pair dobara
        // insert ho jaye → Postgres unique violation (23505) → clean 409.
        catch (DbUpdateException ex) when (
            ex.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation } pg &&
            pg.ConstraintName == "IX_Connections_RequesterId_ReceiverId")
        {
            throw new ConflictException("A connection request between these users already exists.");
        }
    }
}
