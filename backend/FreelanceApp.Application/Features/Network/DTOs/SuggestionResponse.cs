namespace FreelanceApp.Application.Features.Network.DTOs;

public class SuggestionResponse
{
    public Guid UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string? Headline { get; set; }
    public string? PhotoUrl { get; set; }
    public int MutualConnectionsCount { get; set; }
    public IReadOnlyList<string> SharedSkills { get; set; } = [];
    public int Score { get; set; }
}
