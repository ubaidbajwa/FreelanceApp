namespace FreelanceApp.Application.Features.Connections.DTOs;

public class MutualPreview
{
    public Guid UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string? PhotoUrl { get; set; }
}
