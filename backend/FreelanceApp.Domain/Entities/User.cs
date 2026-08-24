using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Domain.Entities;

public class User
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;

    // Nullable: social users (Google/MS/Apple) ke paas password hota hi nahi.
    public string? PasswordHash { get; set; }
    public string FullName { get; set; } = string.Empty;

    // User kaise register hua — local (email+password) ya kisi social provider se.
    public AuthProvider Provider { get; set; } = AuthProvider.Local;

    // Provider ki taraf se user ki unique ID (e.g. Google ka "sub"/subject).
    // Email badal sakti hai, ye ID kabhi nahi — matching ka mazboot sahara.
    public string? ExternalId { get; set; }

    /// <summary>
    /// The user's primary role. This ONLY controls the default experience — which
    /// dashboard/feed to show first when the user opens the app. It is NOT a permission
    /// boundary: what a user is allowed to DO (hire, apply for work) is decided by
    /// capabilities (see <c>UserCapabilities</c>), not by this value. Upwork-style: a
    /// user with a Freelancer primary role can still hire, and vice-versa.
    /// </summary>
    public UserRole PrimaryRole { get; set; } = UserRole.Freelancer;

    public bool IsIdentityVerified { get; set; } = false;
    public bool IsEmailVerified { get; set; }
    public Guid SecurityStamp { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}