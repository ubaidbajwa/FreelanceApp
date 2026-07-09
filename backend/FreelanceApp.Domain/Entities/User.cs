using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Domain.Entities;

public class User
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public UserRole Role { get; set; } = UserRole.Freelancer;
    public bool IsIdentityVerified { get; set; } = false;
    public bool IsEmailVerified { get; set; }
    public Guid SecurityStamp { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}