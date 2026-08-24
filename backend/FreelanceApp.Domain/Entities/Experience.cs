namespace FreelanceApp.Domain.Entities;

public class Experience
{
    public Guid Id { get; set; }
    public Guid ProfileId { get; set; }         // FK — cascade delete with profile

    public string Title { get; set; } = string.Empty;
    public string Company { get; set; } = string.Empty;
    public DateOnly StartDate { get; set; }
    public DateOnly? EndDate { get; set; }      // null = current position
    public string? Description { get; set; }

    // ===== Navigation Property =====
    public Profile? Profile { get; set; }
}
