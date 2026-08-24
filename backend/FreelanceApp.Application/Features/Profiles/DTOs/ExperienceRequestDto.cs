namespace FreelanceApp.Application.Features.Profiles.DTOs;

// Add aur update dono ke liye — same shape
public class ExperienceRequestDto
{
    public string Title { get; set; } = string.Empty;
    public string Company { get; set; } = string.Empty;
    public DateOnly StartDate { get; set; }
    public DateOnly? EndDate { get; set; }      // null = current position
    public string? Description { get; set; }
}
