namespace FreelanceApp.Application.Common.Capabilities;

/// <summary>
/// What a user is allowed to DO right now — computed, never stored. Upwork-style:
/// capabilities are derived from account state (e.g. profile completion), not from a
/// permanent role. These are additive, read-only fields on auth/profile responses.
/// </summary>
public class UserCapabilitiesDto
{
    /// <summary>Every authenticated user can hire.</summary>
    public bool CanHire { get; set; }

    /// <summary>True once the user has a profile that is at least 50% complete.</summary>
    public bool CanFreelance { get; set; }
}
