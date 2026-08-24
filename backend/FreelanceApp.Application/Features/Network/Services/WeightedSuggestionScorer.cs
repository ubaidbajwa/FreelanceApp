using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Features.Network.Models;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Application.Features.Network.Services;

public sealed class WeightedSuggestionScorer(IOptions<SuggestionSettings> options) : ISuggestionScorer
{
    private readonly SuggestionSettings _settings = options.Value;

    public int Score(SuggestionCandidate candidate) =>
        (candidate.MutualConnectionsCount * _settings.MutualConnectionWeight) +
        (candidate.SharedSkills.Count * _settings.SharedSkillWeight);
}
