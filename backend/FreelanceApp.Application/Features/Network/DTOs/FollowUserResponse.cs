namespace FreelanceApp.Application.Features.Network.DTOs;

public class FollowUserResponse
{
    public Guid UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string? Headline { get; set; }
    public string? PhotoUrl { get; set; }
    /// <summary>
    /// Followers list: true if I also follow them (enables "Follow back" button).
    /// Following list: true if they also follow me (mutual follow indicator).
    /// Computed via EXISTS subquery in the same query — no N+1.
    /// </summary>
    public bool IsFollowingBack { get; set; }
}
