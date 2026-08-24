using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace FreelanceApp.Infrastructure.Repositories;

public class FollowRepository(AppDbContext context) : IFollowRepository
{
    public async Task FollowAsync(Guid followerId, Guid followeeId, CancellationToken ct)
    {
        var follow = new Follow
        {
            Id = Guid.NewGuid(),
            FollowerId = followerId,
            FolloweeId = followeeId,
            CreatedAt = DateTime.UtcNow
        };

        await context.Follows.AddAsync(follow, ct);

        try
        {
            await context.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (
            ex.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation } pg &&
            pg.ConstraintName == "IX_Follows_FollowerId_FolloweeId")
        {
            context.ChangeTracker.Clear();
        }
    }

    public async Task UnfollowAsync(Guid followerId, Guid followeeId, CancellationToken ct)
    {
        var follow = await context.Follows
            .FirstOrDefaultAsync(f => f.FollowerId == followerId && f.FolloweeId == followeeId, ct);

        if (follow is null) return;

        context.Follows.Remove(follow);
        await context.SaveChangesAsync(ct);
    }

    public Task<bool> UserExistsAsync(Guid userId, CancellationToken ct) =>
        context.Users.AsNoTracking().AnyAsync(u => u.Id == userId, ct);

    public async Task<PagedResult<FollowUserResponse>> GetFollowersAsync(
        Guid meId, int page, int pageSize, CancellationToken ct)
    {
        // Users who follow meId (FolloweeId == meId).
        // IsFollowingBack = I also follow them (correlated EXISTS, same query — no N+1).
        var baseQuery =
            from f in context.Follows
            where f.FolloweeId == meId
            join u in context.Users on f.FollowerId equals u.Id
            join p in context.Profiles on u.Id equals p.UserId into pg
            from p in pg.DefaultIfEmpty()
            select new { f, u, p };

        var totalCount = await baseQuery.CountAsync(ct);

        var items = await baseQuery
            .OrderByDescending(x => x.f.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x => new FollowUserResponse
            {
                UserId = x.u.Id,
                FullName = x.u.FullName,
                Headline = x.p != null ? x.p.Headline : null,
                PhotoUrl = x.p != null ? x.p.ProfilePhotoUrl : null,
                IsFollowingBack = context.Follows.Any(fb => fb.FollowerId == meId && fb.FolloweeId == x.u.Id)
            })
            .AsNoTracking()
            .ToListAsync(ct);

        return new PagedResult<FollowUserResponse>
        {
            Items = items,
            Page = page,
            PageSize = pageSize,
            TotalCount = totalCount
        };
    }

    public async Task<PagedResult<FollowUserResponse>> GetFollowingAsync(
        Guid meId, int page, int pageSize, CancellationToken ct)
    {
        // Users meId follows (FollowerId == meId).
        // IsFollowingBack = they also follow me (correlated EXISTS, same query — no N+1).
        var baseQuery =
            from f in context.Follows
            where f.FollowerId == meId
            join u in context.Users on f.FolloweeId equals u.Id
            join p in context.Profiles on u.Id equals p.UserId into pg
            from p in pg.DefaultIfEmpty()
            select new { f, u, p };

        var totalCount = await baseQuery.CountAsync(ct);

        var items = await baseQuery
            .OrderByDescending(x => x.f.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x => new FollowUserResponse
            {
                UserId = x.u.Id,
                FullName = x.u.FullName,
                Headline = x.p != null ? x.p.Headline : null,
                PhotoUrl = x.p != null ? x.p.ProfilePhotoUrl : null,
                IsFollowingBack = context.Follows.Any(fb => fb.FollowerId == x.u.Id && fb.FolloweeId == meId)
            })
            .AsNoTracking()
            .ToListAsync(ct);

        return new PagedResult<FollowUserResponse>
        {
            Items = items,
            Page = page,
            PageSize = pageSize,
            TotalCount = totalCount
        };
    }

    public async Task<(bool IsFollowing, bool IsFollowedBy)> GetFollowStatusAsync(
        Guid meId, Guid targetId, CancellationToken ct)
    {
        var result = await context.Follows
            .AsNoTracking()
            .Where(f => (f.FollowerId == meId && f.FolloweeId == targetId) ||
                        (f.FollowerId == targetId && f.FolloweeId == meId))
            .GroupBy(_ => 0)
            .Select(g => new
            {
                IsFollowing = g.Any(f => f.FollowerId == meId && f.FolloweeId == targetId),
                IsFollowedBy = g.Any(f => f.FollowerId == targetId && f.FolloweeId == meId)
            })
            .FirstOrDefaultAsync(ct);

        return result is null ? (false, false) : (result.IsFollowing, result.IsFollowedBy);
    }

    public async Task<(int Following, int Followers)> GetFollowCountsAsync(Guid meId, CancellationToken ct)
    {
        // Single query — same GroupBy(_ => 0) + null-fallback pattern as ConnectionRepository.GetCountsAsync.
        var counts = await context.Follows
            .AsNoTracking()
            .Where(f => f.FollowerId == meId || f.FolloweeId == meId)
            .GroupBy(_ => 0)
            .Select(g => new
            {
                Following = g.Count(f => f.FollowerId == meId),
                Followers = g.Count(f => f.FolloweeId == meId)
            })
            .FirstOrDefaultAsync(ct);

        return counts is null ? (0, 0) : (counts.Following, counts.Followers);
    }

    // ── Follow-suggestion queries ─────────────────────────────────────────────

    public async Task<List<Guid>> GetMyAcceptedConnectionIdsAsync(Guid meId, CancellationToken ct)
    {
        return await context.Connections
            .AsNoTracking()
            .Where(c => c.Status == ConnectionStatus.Accepted &&
                       (c.RequesterId == meId || c.ReceiverId == meId))
            .Select(c => c.RequesterId == meId ? c.ReceiverId : c.RequesterId)
            .ToListAsync(ct);
    }

    public async Task<List<string>> GetMySkillsAsync(Guid meId, CancellationToken ct)
    {
        var skills = await context.Profiles
            .AsNoTracking()
            .Where(p => p.UserId == meId)
            .Select(p => p.Skills)
            .FirstOrDefaultAsync(ct);

        return skills ?? [];
    }

    public async Task<List<Guid>> GetFollowSuggestionCandidateIdsAsync(
        Guid meId,
        IReadOnlyList<Guid> myConnectionIds,
        string[] mySkillsLower,
        int topPopularCount,
        CancellationToken ct)
    {
        // Already-followed subquery — reused by all three candidate queries below.
        var alreadyFollowingIds = context.Follows
            .Where(f => f.FollowerId == meId)
            .Select(f => f.FolloweeId);

        // Follow-dismissed exclusion — Kind=Follow only; connect-dismissals do not affect this feed.
        var followDismissedIds = context.SuggestionDismissals
            .Where(d => d.UserId == meId && d.Kind == SuggestionKind.Follow)
            .Select(d => d.DismissedUserId);

        // ── Query A: Social graph reach ──────────────────────────────────────────
        // Users followed by people I have an Accepted connection with.
        // Deliberately does NOT exclude my own connections — Follow and Connection
        // are independent, so following a connection is valid and expected. This is
        // intentionally different from connect-suggestions which excludes connections.
        List<Guid> queryAIds = [];
        if (myConnectionIds.Count > 0)
        {
            queryAIds = await context.Follows
                .AsNoTracking()
                .Where(f => myConnectionIds.Contains(f.FollowerId)
                         && f.FolloweeId != meId
                         && !alreadyFollowingIds.Contains(f.FolloweeId)
                         && !followDismissedIds.Contains(f.FolloweeId))
                .Select(f => f.FolloweeId)
                .Distinct()
                .ToListAsync(ct);
        }

        // ── Query B: Skill overlap ───────────────────────────────────────────────
        // Case-insensitive: mySkillsLower are pre-lowercased in the service.
        // FromSqlInterpolated is required because EF Core cannot translate unnest().
        // The GIN index IX_Profiles_Skills_GIN accelerates the array EXISTS scan.
        List<Guid> queryBIds = [];
        if (mySkillsLower.Length > 0)
        {
            queryBIds = await context.Profiles
                .FromSqlInterpolated($"""
                    SELECT * FROM "Profiles"
                    WHERE EXISTS (
                        SELECT 1 FROM unnest("Skills") AS s WHERE lower(s) = ANY({mySkillsLower})
                    )
                    """)
                .AsNoTracking()
                .Where(p => p.UserId != meId
                         && !alreadyFollowingIds.Contains(p.UserId)
                         && !followDismissedIds.Contains(p.UserId))
                .Select(p => p.UserId)
                .ToListAsync(ct);
        }

        // ── Query C: Global popularity ───────────────────────────────────────────
        // Top N most-followed users overall. Cold-start path: a brand-new user with
        // no connections and no skills still receives results from here. This is the
        // key behavioural difference from connect-suggestions, which has no cold-start
        // path. Backed by IX_Follows_FolloweeId.
        var queryCIds = await context.Follows
            .AsNoTracking()
            .Where(f => f.FolloweeId != meId
                     && !alreadyFollowingIds.Contains(f.FolloweeId)
                     && !followDismissedIds.Contains(f.FolloweeId))
            .GroupBy(f => f.FolloweeId)
            .OrderByDescending(g => g.Count())
            .Take(topPopularCount)
            .Select(g => g.Key)
            .ToListAsync(ct);

        return queryAIds.Union(queryBIds).Union(queryCIds).ToList();
    }

    public async Task<List<(User User, Profile? Profile)>> LoadFollowSuggestionDetailsAsync(
        IReadOnlyList<Guid> candidateIds, CancellationToken ct)
    {
        var query =
            from u in context.Users
            where candidateIds.Contains(u.Id)
            join p in context.Profiles on u.Id equals p.UserId into pg
            from p in pg.DefaultIfEmpty()
            select new { User = u, Profile = p };

        var rawItems = await query.AsNoTracking().ToListAsync(ct);
        return rawItems.Select(x => (x.User, (Profile?)x.Profile)).ToList();
    }

    public async Task<Dictionary<Guid, int>> GetFollowerCountsForCandidatesAsync(
        IReadOnlyList<Guid> candidateIds, CancellationToken ct)
    {
        if (candidateIds.Count == 0) return [];

        var counts = await context.Follows
            .AsNoTracking()
            .Where(f => candidateIds.Contains(f.FolloweeId))
            .GroupBy(f => f.FolloweeId)
            .Select(g => new { UserId = g.Key, Count = g.Count() })
            .ToListAsync(ct);

        return counts.ToDictionary(x => x.UserId, x => x.Count);
    }

    public async Task<Dictionary<Guid, SocialReachData>> GetSocialReachDataAsync(
        IReadOnlyList<Guid> candidateIds,
        IReadOnlyList<Guid> myConnectionIds,
        CancellationToken ct)
    {
        if (candidateIds.Count == 0 || myConnectionIds.Count == 0) return [];

        // Single round trip: fetch all (candidateId, followerId, fullName, photoUrl) rows,
        // then group in C# to build per-candidate count + 3-user preview. No N+1.
        var rows = await (
            from f in context.Follows
            where candidateIds.Contains(f.FolloweeId) && myConnectionIds.Contains(f.FollowerId)
            join u in context.Users on f.FollowerId equals u.Id
            join p in context.Profiles on f.FollowerId equals p.UserId into pg
            from p in pg.DefaultIfEmpty()
            select new
            {
                CandidateId = f.FolloweeId,
                FollowerId  = f.FollowerId,
                FullName    = u.FullName,
                PhotoUrl    = p != null ? p.ProfilePhotoUrl : null
            })
            .AsNoTracking()
            .ToListAsync(ct);

        return rows
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
    }

    public async Task DismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct)
    {
        var dismissal = new SuggestionDismissal
        {
            Id = Guid.NewGuid(),
            UserId = meId,
            DismissedUserId = dismissedUserId,
            Kind = kind,
            CreatedAt = DateTime.UtcNow
        };

        await context.SuggestionDismissals.AddAsync(dismissal, ct);

        try
        {
            await context.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (
            ex.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation } pg &&
            pg.ConstraintName == "IX_SuggestionDismissals_UserId_DismissedUserId_Kind")
        {
            context.ChangeTracker.Clear();
        }
    }

    public async Task UndismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct)
    {
        var row = await context.SuggestionDismissals
            .FirstOrDefaultAsync(d => d.UserId == meId && d.DismissedUserId == dismissedUserId && d.Kind == kind, ct);

        if (row is null) return;

        context.SuggestionDismissals.Remove(row);
        await context.SaveChangesAsync(ct);
    }
}
