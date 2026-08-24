using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Npgsql;

namespace FreelanceApp.Infrastructure.Repositories;

public class SuggestionRepository(
    AppDbContext context,
    ILogger<SuggestionRepository> logger) : ISuggestionRepository
{
    public async Task<List<(User User, Profile? Profile)>> GetCandidatesAsync(
        Guid meId, IReadOnlyList<string> mySkillsLower, int cap, CancellationToken ct)
    {
        // Shared exclusion subqueries (used by both Query A and B)
        var excludedIds = context.Connections
            .Where(c => (c.RequesterId == meId || c.ReceiverId == meId)
                     && c.Status != ConnectionStatus.Rejected)
            .Select(c => c.RequesterId == meId ? c.ReceiverId : c.RequesterId);

        var dismissedIds = context.SuggestionDismissals
            .Where(d => d.UserId == meId && d.Kind == SuggestionKind.Connect)
            .Select(d => d.DismissedUserId);

        // ── Query A: Friends-of-Friends ──────────────────────────────────────────────
        // Finds users who share at least one Accepted connection with me.
        // Uses IX_Connections_RequesterId_Status and IX_Connections_ReceiverId_Status
        // (added in AddSuggestionPerformanceIndexes) for index-backed lookups.
        // Runs entirely server-side as correlated EXISTS/IN subqueries.
        var myFriendsAsRequester = context.Connections
            .Where(c => c.Status == ConnectionStatus.Accepted && c.RequesterId == meId)
            .Select(c => c.ReceiverId);

        var myFriendsAsReceiver = context.Connections
            .Where(c => c.Status == ConnectionStatus.Accepted && c.ReceiverId == meId)
            .Select(c => c.RequesterId);

        var myFriendIds = myFriendsAsRequester.Union(myFriendsAsReceiver);

        var fofViaRequester = context.Connections
            .Where(c => c.Status == ConnectionStatus.Accepted
                     && myFriendIds.Contains(c.RequesterId)
                     && c.ReceiverId != meId
                     && !myFriendIds.Contains(c.ReceiverId)
                     && !excludedIds.Contains(c.ReceiverId)
                     && !dismissedIds.Contains(c.ReceiverId))
            .Select(c => c.ReceiverId);

        var fofViaReceiver = context.Connections
            .Where(c => c.Status == ConnectionStatus.Accepted
                     && myFriendIds.Contains(c.ReceiverId)
                     && c.RequesterId != meId
                     && !myFriendIds.Contains(c.RequesterId)
                     && !excludedIds.Contains(c.RequesterId)
                     && !dismissedIds.Contains(c.RequesterId))
            .Select(c => c.RequesterId);

        var fofIds = await fofViaRequester
            .Union(fofViaReceiver)
            .ToListAsync(ct);

        // ── Query B: Skill-Overlap ────────────────────────────────────────────────────
        // Case-insensitive approach: mySkillsLower contains skills already lowercased in C#.
        // FromSqlInterpolated generates:
        //   EXISTS (SELECT 1 FROM unnest("Skills") AS s WHERE lower(s) = ANY(@p0))
        // which runs entirely in PostgreSQL. The GIN index on "Skills" accelerates
        // array operations on the column (AddSuggestionPerformanceIndexes migration).
        var skillIds = new List<Guid>();
        if (mySkillsLower.Count > 0)
        {
            var mySkillsArray = mySkillsLower.ToArray();
            skillIds = await context.Profiles
                .FromSqlInterpolated($"""
                    SELECT * FROM "Profiles"
                    WHERE EXISTS (
                        SELECT 1 FROM unnest("Skills") AS s WHERE lower(s) = ANY({mySkillsArray})
                    )
                    """)
                .AsNoTracking()
                .Where(p => p.UserId != meId
                         && !excludedIds.Contains(p.UserId)
                         && !dismissedIds.Contains(p.UserId))
                .Select(p => p.UserId)
                .ToListAsync(ct);
        }

        // Union + dedup; warn when cap is hit (real candidates were dropped)
        var allIds = fofIds.Union(skillIds).ToList();
        if (allIds.Count > cap)
        {
            logger.LogWarning(
                "Suggestion candidate cap ({Cap}) reached for user {UserId}; pool was {Total}. " +
                "Some candidates were dropped — consider increasing MaxCandidates or moving to precomputed scores.",
                cap, meId, allIds.Count);
            allIds = allIds.Take(cap).ToList();
        }

        if (allIds.Count == 0) return [];

        // Load User + Profile (LEFT JOIN) in one round trip
        var query =
            from u in context.Users
            where allIds.Contains(u.Id)
            join p in context.Profiles on u.Id equals p.UserId into pg
            from p in pg.DefaultIfEmpty()
            select new { User = u, Profile = p };

        var rawItems = await query.AsNoTracking().ToListAsync(ct);
        return rawItems.Select(x => (x.User, (Profile?)x.Profile)).ToList();
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

    public async Task<HashSet<Guid>> GetMyAcceptedConnectionIdsAsync(Guid meId, CancellationToken ct)
    {
        var ids = await context.Connections
            .AsNoTracking()
            .Where(c => c.Status == ConnectionStatus.Accepted &&
                       (c.RequesterId == meId || c.ReceiverId == meId))
            .Select(c => c.RequesterId == meId ? c.ReceiverId : c.RequesterId)
            .ToListAsync(ct);

        return [.. ids];
    }

    public async Task<Dictionary<Guid, HashSet<Guid>>> GetCandidateConnectionIdsAsync(
        IReadOnlyList<Guid> candidateIds, CancellationToken ct)
    {
        if (candidateIds.Count == 0) return [];

        var rows = await context.Connections
            .AsNoTracking()
            .Where(c => c.Status == ConnectionStatus.Accepted &&
                       (candidateIds.Contains(c.RequesterId) || candidateIds.Contains(c.ReceiverId)))
            .Select(c => new { c.RequesterId, c.ReceiverId })
            .ToListAsync(ct);

        var dict = candidateIds.ToDictionary(id => id, _ => new HashSet<Guid>());

        foreach (var row in rows)
        {
            if (dict.TryGetValue(row.RequesterId, out var setA)) setA.Add(row.ReceiverId);
            if (dict.TryGetValue(row.ReceiverId, out var setB)) setB.Add(row.RequesterId);
        }

        return dict;
    }

    public async Task DismissAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct)
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

    public async Task UndismissAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct)
    {
        var row = await context.SuggestionDismissals
            .FirstOrDefaultAsync(d => d.UserId == meId && d.DismissedUserId == dismissedUserId && d.Kind == kind, ct);

        if (row is null) return;

        context.SuggestionDismissals.Remove(row);
        await context.SaveChangesAsync(ct);
    }
}
