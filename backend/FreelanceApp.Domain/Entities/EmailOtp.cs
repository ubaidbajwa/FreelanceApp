using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Domain.Entities;

public class EmailOtp
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Code { get; set; } = string.Empty;
    public OtpPurpose Purpose { get; set; }
    public DateTime ExpiresAt { get; set; }
    public bool IsUsed { get; set; }
    public int AttemptCount { get; set; }
    public DateTime CreatedAt { get; set; }

    // Navigation property (relationship to User)
    public User? User { get; set; }
}