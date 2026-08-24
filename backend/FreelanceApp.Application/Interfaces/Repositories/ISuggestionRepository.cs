using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface ISuggestionRepository
{
    // mySkillsLower: caller provides already-lowercased skills so server-side SQL can do
    // lower(unnest("Skills")) = ANY(@mySkillsLower) for case-insensitive comparison.
    Task<List<(User User, Profile? Profile)>> GetCandidatesAsync(
        Guid meId, IReadOnlyList<string> mySkillsLower, int cap, CancellationToken ct);

    Task<List<string>> GetMySkillsAsync(Guid meId, CancellationToken ct);

    // Single query — all users I am Accepted-connected with, needed for mutual counting.
    Task<HashSet<Guid>> GetMyAcceptedConnectionIdsAsync(Guid meId, CancellationToken ct);

    // Accepted connection partner IDs for each candidate (one query over the bounded set).
    Task<Dictionary<Guid, HashSet<Guid>>> GetCandidateConnectionIdsAsync(
        IReadOnlyList<Guid> candidateIds, CancellationToken ct);

    // kind is REQUIRED — no default — omitting it is a compile error, not a silent bug
    // that causes a dismissal to vanish from the wrong feed.
    Task DismissAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct);

    // kind is REQUIRED — no default — same reason as DismissAsync.
    Task UndismissAsync(Guid meId, Guid dismissedUserId, SuggestionKind kind, CancellationToken ct);
}
