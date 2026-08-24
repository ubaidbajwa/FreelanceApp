using FreelanceApp.Application.Features.Network.Models;

namespace FreelanceApp.Application.Interfaces.Services;

// Seam for replacing the ranking model without touching the service, controller, or DTOs.
// Current implementation: WeightedSuggestionScorer (mutuals*weight + skills*weight).
// Future: inject a precomputed/ML scorer that reads from a scores table.
public interface ISuggestionScorer
{
    int Score(SuggestionCandidate candidate);
}
