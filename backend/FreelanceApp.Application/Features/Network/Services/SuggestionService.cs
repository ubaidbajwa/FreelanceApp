using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Application.Features.Network.Services;

public sealed class SuggestionService(
    ISuggestionRepository repo,
    ISuggestionScorer scorer,
    ISuggestionCache cache,
    IOptions<SuggestionSettings> options) : ISuggestionService
{
    // In-memory scoring over a bounded candidate set. Fine for current scale (thousands of users).
    // At large scale this must move to precomputed scores / a background job. Deliberate simplification.
    public const int MaxPageSize = 50;
    private readonly SuggestionSettings _settings = options.Value;

    public async Task<PagedResult<SuggestionResponse>> GetSuggestionsAsync(
        Guid meId, int page, int pageSize, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        if (_settings.CacheSeconds > 0)
        {
            var cached = await cache.GetAsync(meId, page, pageSize, ct);
            if (cached is not null) return cached;
        }

        var mySkills = await repo.GetMySkillsAsync(meId, ct);
        var mySkillsLower = mySkills.Select(s => s.ToLower()).ToList();

        var candidates = await repo.GetCandidatesAsync(meId, mySkillsLower, _settings.MaxCandidates, ct);
        var myAcceptedIds = await repo.GetMyAcceptedConnectionIdsAsync(meId, ct);

        var candidateIds = candidates.Select(c => c.User.Id).ToList();
        var candidateConnectionIds = await repo.GetCandidateConnectionIdsAsync(candidateIds, ct);

        var mySkillsLowerSet = mySkillsLower.ToHashSet();

        var scored = candidates
            .Select(c =>
            {
                var theirAcceptedIds = candidateConnectionIds.GetValueOrDefault(c.User.Id, []);
                var mutualCount = myAcceptedIds.Count(id => theirAcceptedIds.Contains(id));

                var candidateSkills = c.Profile?.Skills ?? [];
                var theirSkillsLower = candidateSkills.Select(s => s.ToLower()).ToHashSet();
                var sharedSkillsLower = mySkillsLowerSet.Intersect(theirSkillsLower).ToHashSet();

                // Preserve candidate's original casing for the reason chip
                var sharedSkills = candidateSkills
                    .Where(s => sharedSkillsLower.Contains(s.ToLower()))
                    .ToList<string>();

                var candidate = new SuggestionCandidate(
                    c.User.Id, c.User.FullName,
                    c.Profile?.Headline, c.Profile?.ProfilePhotoUrl,
                    mutualCount, sharedSkills, c.User.CreatedAt);

                var score = scorer.Score(candidate);
                return (Candidate: candidate, Score: score);
            })
            .Where(x => x.Score > 0)
            .OrderByDescending(x => x.Score)
            .ThenByDescending(x => x.Candidate.CreatedAt)
            .ToList();

        var totalCount = scored.Count;
        var items = scored
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x => new SuggestionResponse
            {
                UserId = x.Candidate.UserId,
                FullName = x.Candidate.FullName,
                Headline = x.Candidate.Headline,
                PhotoUrl = x.Candidate.PhotoUrl,
                MutualConnectionsCount = x.Candidate.MutualConnectionsCount,
                SharedSkills = x.Candidate.SharedSkills,
                Score = x.Score
            })
            .ToList();

        var result = new PagedResult<SuggestionResponse>
        {
            Items = items,
            Page = page,
            PageSize = pageSize,
            TotalCount = totalCount
        };

        if (_settings.CacheSeconds > 0)
            await cache.SetAsync(meId, page, pageSize, result, _settings.CacheSeconds, ct);

        return result;
    }

    public async Task DismissAsync(Guid meId, Guid dismissedUserId, CancellationToken ct = default)
    {
        if (meId == dismissedUserId)
            throw new ValidationException("Cannot dismiss yourself.");

        await repo.DismissAsync(meId, dismissedUserId, SuggestionKind.Connect, ct);
    }

    public Task UndismissAsync(Guid meId, Guid dismissedUserId, CancellationToken ct = default) =>
        repo.UndismissAsync(meId, dismissedUserId, SuggestionKind.Connect, ct);
}
