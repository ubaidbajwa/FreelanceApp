using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Application.Features.Network.Services;

public sealed class FollowService(
    IFollowRepository repo,
    IFollowSuggestionScorer scorer,
    IOptions<SuggestionSettings> options,
    ILogger<FollowService> logger) : IFollowService
{
    public const int MaxPageSize = 50;
    private readonly SuggestionSettings _settings = options.Value;

    public async Task FollowAsync(Guid followerId, Guid followeeId, CancellationToken ct = default)
    {
        if (followerId == followeeId)
            throw new ValidationException("Cannot follow yourself.");

        if (!await repo.UserExistsAsync(followeeId, ct))
            throw new NotFoundException("User not found.");

        await repo.FollowAsync(followerId, followeeId, ct);
    }

    public Task UnfollowAsync(Guid followerId, Guid followeeId, CancellationToken ct = default) =>
        repo.UnfollowAsync(followerId, followeeId, ct);

    public async Task<PagedResult<FollowUserResponse>> GetFollowersAsync(
        Guid meId, int page, int pageSize, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);
        return await repo.GetFollowersAsync(meId, page, pageSize, ct);
    }

    public async Task<PagedResult<FollowUserResponse>> GetFollowingAsync(
        Guid meId, int page, int pageSize, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);
        return await repo.GetFollowingAsync(meId, page, pageSize, ct);
    }

    public async Task<FollowStatusResponse> GetFollowStatusAsync(
        Guid meId, Guid targetId, CancellationToken ct = default)
    {
        var (isFollowing, isFollowedBy) = await repo.GetFollowStatusAsync(meId, targetId, ct);
        return new FollowStatusResponse(isFollowing, isFollowedBy);
    }

    public async Task<PagedResult<FollowSuggestionResponse>> GetFollowSuggestionsAsync(
        Guid meId, int page, int pageSize, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);

        // ── 1. Gather caller context (2 round trips) ─────────────────────────
        var mySkills = await repo.GetMySkillsAsync(meId, ct);
        var mySkillsLower = mySkills.Select(s => s.ToLower()).ToList();
        var myConnectionIds = await repo.GetMyAcceptedConnectionIdsAsync(meId, ct);

        // ── 2. Signal-driven candidate selection (3 round trips: A, B, C) ────
        var candidateIds = await repo.GetFollowSuggestionCandidateIdsAsync(
            meId, myConnectionIds, mySkillsLower.ToArray(), _settings.TopPopularCandidates, ct);

        if (candidateIds.Count > _settings.MaxCandidates)
        {
            logger.LogWarning(
                "Follow-suggestion candidate cap ({Cap}) reached for user {UserId}; pool was {Total}. " +
                "Consider increasing MaxCandidates or moving to precomputed scores.",
                _settings.MaxCandidates, meId, candidateIds.Count);
            candidateIds = candidateIds.Take(_settings.MaxCandidates).ToList();
        }

        if (candidateIds.Count == 0)
            return new PagedResult<FollowSuggestionResponse>
                { Items = [], Page = page, PageSize = pageSize, TotalCount = 0 };

        // ── 3. Fixed additional queries over the bounded set (3 round trips) ─
        // No query is issued inside a loop over candidates.
        var details = await repo.LoadFollowSuggestionDetailsAsync(candidateIds, ct);
        var followerCounts = await repo.GetFollowerCountsForCandidatesAsync(candidateIds, ct);
        var socialReachData = await repo.GetSocialReachDataAsync(candidateIds, myConnectionIds, ct);

        var mySkillsLowerSet = mySkillsLower.ToHashSet();

        // ── 4. In-memory scoring ─────────────────────────────────────────────
        var scored = details
            .Select(d =>
            {
                var candidateSkills = d.Profile?.Skills ?? [];
                var theirSkillsLower = candidateSkills.Select(s => s.ToLower()).ToHashSet();
                var sharedSkillsLower = mySkillsLowerSet.Intersect(theirSkillsLower).ToHashSet();

                // Preserve candidate's original casing for the response chip.
                var sharedSkills = (IReadOnlyList<string>)candidateSkills
                    .Where(s => sharedSkillsLower.Contains(s.ToLower()))
                    .ToList();

                var followersCount = followerCounts.GetValueOrDefault(d.User.Id, 0);
                var reach = socialReachData.GetValueOrDefault(d.User.Id);

                var candidate = new FollowSuggestionCandidate(
                    d.User.Id,
                    followersCount,
                    sharedSkills.Count,
                    reach?.Count ?? 0);

                return new
                {
                    UserId = d.User.Id,
                    FullName = d.User.FullName,
                    Headline = d.Profile?.Headline,
                    PhotoUrl = d.Profile?.ProfilePhotoUrl,
                    FollowersCount = followersCount,
                    SharedSkills = sharedSkills,
                    FollowedByPreview = (IReadOnlyList<SocialProofUser>)(reach?.Preview ?? []),
                    Score = scorer.Score(candidate)
                };
            })
            // Unlike connect-suggestions, zero-score candidates ARE kept — following is
            // low-commitment and a cold-start feed of popular accounts is useful, not noise.
            .OrderByDescending(x => x.Score)
            .ThenByDescending(x => x.FollowersCount)
            .ThenBy(x => x.UserId) // stable deterministic tiebreaker for consistent paging
            .ToList();

        var totalCount = scored.Count;
        var items = scored
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x => new FollowSuggestionResponse
            {
                UserId = x.UserId,
                FullName = x.FullName,
                Headline = x.Headline,
                PhotoUrl = x.PhotoUrl,
                FollowersCount = x.FollowersCount,
                SharedSkills = x.SharedSkills,
                FollowedByPreview = x.FollowedByPreview,
                Score = x.Score
            })
            .ToList();

        return new PagedResult<FollowSuggestionResponse>
        {
            Items = items,
            Page = page,
            PageSize = pageSize,
            TotalCount = totalCount
        };
    }

    public async Task DismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, CancellationToken ct = default)
    {
        if (meId == dismissedUserId)
            throw new ValidationException("Cannot dismiss yourself.");

        if (!await repo.UserExistsAsync(dismissedUserId, ct))
            throw new NotFoundException("User not found.");

        await repo.DismissFollowSuggestionAsync(meId, dismissedUserId, SuggestionKind.Follow, ct);
    }

    public Task UndismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, CancellationToken ct = default) =>
        repo.UndismissFollowSuggestionAsync(meId, dismissedUserId, SuggestionKind.Follow, ct);
}
