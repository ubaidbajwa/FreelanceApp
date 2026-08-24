namespace FreelanceApp.Application.Features.Network.Models;

// Internal scoring context — not a DTO. IFollowSuggestionScorer receives this;
// the scorer's return value becomes FollowSuggestionResponse.Score.
public sealed record FollowSuggestionCandidate(
    Guid UserId,
    int FollowersCount,
    int SharedSkillsCount,
    // How many of the caller's accepted connections follow this candidate.
    // We count them now even though the preview names (N6b) are out of scope.
    int SocialReachCount);
