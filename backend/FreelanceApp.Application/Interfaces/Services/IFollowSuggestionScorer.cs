using FreelanceApp.Application.Features.Network.Models;

namespace FreelanceApp.Application.Interfaces.Services;

// Seam for replacing the follow-suggestion ranking algorithm without touching
// FollowService or the controller. Deliberately separate from ISuggestionScorer
// because the formula differs (no mutual-connection signal; adds social reach + popularity cap).
public interface IFollowSuggestionScorer
{
    int Score(FollowSuggestionCandidate candidate);
}
