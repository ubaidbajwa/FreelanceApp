namespace FreelanceApp.Application.Features.Connections.DTOs;

// Incoming/outgoing pending request — counterpart user ke card ke sath
public class PendingRequestDto
{
    public Guid ConnectionId { get; set; }
    public ConnectionUserDto User { get; set; } = new();
    public DateTime CreatedAt { get; set; }

    // Additive — mutual-connection context for incoming invitations.
    // Zero mutuals: count=0, preview=[] (never null).
    public int MutualConnectionsCount { get; set; }
    public IReadOnlyList<MutualPreview> MutualPreview { get; set; } = [];
}
