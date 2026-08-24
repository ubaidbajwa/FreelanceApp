namespace FreelanceApp.Application.Features.Network.DTOs;

public class FollowSuggestionResponse
{
    public Guid UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string? Headline { get; set; }
    public string? PhotoUrl { get; set; }
    public int FollowersCount { get; set; }
    public IReadOnlyList<string> SharedSkills { get; set; } = [];
    public int Score { get; set; }
    // At most 3 of my connections who also follow this person; empty list when zero proof.
    public IReadOnlyList<SocialProofUser> FollowedByPreview { get; set; } = [];
}
