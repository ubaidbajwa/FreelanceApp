namespace FreelanceApp.Application.Features.Network.Models;

// Internal scoring context — not a DTO. ISuggestionScorer receives this;
// the scorer's return value becomes SuggestionResponse.Score.
public sealed record SuggestionCandidate(
    Guid UserId,
    string FullName,
    string? Headline,
    string? PhotoUrl,
    int MutualConnectionsCount,
    IReadOnlyList<string> SharedSkills,
    DateTime CreatedAt);
