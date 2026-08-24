namespace FreelanceApp.Application.Features.Profiles.DTOs;

public class ExperienceResponseDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Company { get; set; } = string.Empty;
    public DateOnly StartDate { get; set; }
    public DateOnly? EndDate { get; set; }      // null = current position
    public string? Description { get; set; }
}
