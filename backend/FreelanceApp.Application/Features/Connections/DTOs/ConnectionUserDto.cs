namespace FreelanceApp.Application.Features.Connections.DTOs;

// Doosray user ka card — connections list aur pending requests mein dikhta hai
public class ConnectionUserDto
{
    public Guid UserId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Headline { get; set; }
    public string? ProfilePhotoUrl { get; set; }
}
