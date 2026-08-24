using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface IFollowRepository
{
    Task FollowAsync(Guid followerId, Guid followeeId, CancellationToken ct);
    Task UnfollowAsync(Guid followerId, Guid followeeId, CancellationToken ct);
    Task<bool> UserExistsAsync(Guid userId, CancellationToken ct);

    /// <summary>
    /// People who follow <paramref name="meId"/>.
    /// IsFollowingBack is computed in a single query via EXISTS subquery — no N+1.
    /// </summary>
    Task<PagedResult<FollowUserResponse>> GetFollowersAsync(
        Guid meId, int page, int pageSize, CancellationToken ct);

    /// <summary>
    /// People <paramref name="meId"/> follows.
    /// IsFollowingBack is computed in a single query via EXISTS subquery — no N+1.
    /// </summary>
    Task<PagedResult<FollowUserResponse>> GetFollowingAsync(
        Guid meId, int page, int pageSize, CancellationToken ct);

    Task<(bool IsFollowing, bool IsFollowedBy)> GetFollowStatusAsync(
        Guid meId, Guid targetId, CancellationToken ct);

    /// <summary>
    /// Returns (following, followers) counts in a single GroupBy query.
    /// Returns (0, 0) when the user has no follow rows (null-fallback from FirstOrDefault).
    /// </summary>
    Task<(int Following, int Followers)> GetFollowCountsAsync(Guid meId, CancellationToken ct);

    // ── Follow-suggestion queries ─────────────────────────────────────────────

    /// <summary>IDs of users <paramref name="meId"/> has an Accepted connection with.</summary>
    Task<List<Guid>> GetMyAcceptedConnectionIdsAsync(Guid meId, CancellationToken ct);

    /// <summary>Skills from <paramref name="meId"/>'s profile (empty list when no profile).</summary>
    Task<List<string>> GetMySkillsAsync(Guid meId, CancellationToken ct);

    /// <summary>
    /// Signal-driven candidate selection: UNION of
    ///   Query A — social graph reach (users followed by my accepted connections),
    ///   Query B — skill overlap (profiles whose Skills intersect mySkillsLower, server-side),
    ///   Query C — global popularity (top <paramref name="topPopularCount"/> most-followed users).
    /// Exclusions: <paramref name="meId"/> and anyone <paramref name="meId"/> already follows.
    /// Connections are deliberately NOT excluded — Follow and Connection are independent.
    /// Returns de-duplicated Guid list; capping is the caller's responsibility.
    /// </summary>
    Task<List<Guid>> GetFollowSuggestionCandidateIdsAsync(
        Guid meId,
        IReadOnlyList<Guid> myConnectionIds,
        string[] mySkillsLower,
        int topPopularCount,
        CancellationToken ct);

    /// <summary>
    /// Loads User + Profile (LEFT JOIN) for a bounded set of candidate IDs.
    /// Single round trip — no N+1.
    /// </summary>
    Task<List<(User User, Profile? Profile)>> LoadFollowSuggestionDetailsAsync(
        IReadOnlyList<Guid> candidateIds, CancellationToken ct);

    /// <summary>
    /// GROUP BY FolloweeId over Follows WHERE FolloweeId IN candidateIds.
    /// Single round trip — no N+1.
    /// </summary>
    Task<Dictionary<Guid, int>> GetFollowerCountsForCandidatesAsync(
        IReadOnlyList<Guid> candidateIds, CancellationToken ct);

    /// <summary>
    /// For each candidate: how many of <paramref name="myConnectionIds"/> follow them, plus a
    /// preview of up to 3 such connections ordered by FullName (then UserId for stability).
    /// Single round trip — fetches all matching rows then groups in C#. No N+1.
    /// </summary>
    Task<Dictionary<Guid, SocialReachData>> GetSocialReachDataAsync(
        IReadOnlyList<Guid> candidateIds,
        IReadOnlyList<Guid> myConnectionIds,
        CancellationToken ct);

    // kind is REQUIRED — no default — omitting it is a compile error, not a silent misfire
    // that dismisses a user from the wrong feed.
    Task DismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct);

    // kind is REQUIRED — no default — same reason as DismissFollowSuggestionAsync.
    Task UndismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct);
}
