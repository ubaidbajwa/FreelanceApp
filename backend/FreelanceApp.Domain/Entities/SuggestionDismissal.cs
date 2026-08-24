using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Domain.Entities;

public class SuggestionDismissal
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }            // who dismissed
    public Guid DismissedUserId { get; set; }   // who was dismissed
    public SuggestionKind Kind { get; set; }    // which feed this dismissal applies to
    public DateTime CreatedAt { get; set; }

    public User? User { get; set; }
    public User? DismissedUser { get; set; }
}
