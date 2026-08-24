using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Application.Features.Network.Services;

public sealed class WeightedFollowSuggestionScorer(IOptions<SuggestionSettings> options) : IFollowSuggestionScorer
{
    private readonly SuggestionSettings _settings = options.Value;

    public int Score(FollowSuggestionCandidate candidate) =>
        (candidate.SocialReachCount * _settings.SocialReachWeight) +
        (candidate.SharedSkillsCount * _settings.SharedSkillWeight) +
        // Popularity is deliberately capped so a single mega-followed account cannot
        // dominate every user's feed — it acts as a tiebreaker, not the primary signal.
        Math.Min(candidate.FollowersCount, _settings.MaxPopularityBonus);
}
