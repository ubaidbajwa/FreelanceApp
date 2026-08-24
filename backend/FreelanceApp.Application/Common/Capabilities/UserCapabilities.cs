namespace FreelanceApp.Application.Common.Capabilities;

/// <summary>
/// THE single source of truth for capability rules. Anything that needs to know what a
/// user can do (auth response, profile response, future work-action endpoints) must go
/// through here — do not re-implement these checks elsewhere.
/// </summary>
public static class UserCapabilities
{
    /// <summary>Minimum profile completion (%) required before a user can freelance.</summary>
    public const int FreelanceCompletionThreshold = 50;

    /// <summary>
    /// Evaluate capabilities from account state.
    /// <para>CanHire  = true for every authenticated user.</para>
    /// <para>CanFreelance = the user has a profile AND it is at least
    /// <see cref="FreelanceCompletionThreshold"/>% complete.</para>
    /// </summary>
    public static UserCapabilitiesDto Evaluate(bool profileExists, int completionPercent) => new()
    {
        CanHire = true,
        CanFreelance = profileExists && completionPercent >= FreelanceCompletionThreshold
    };
}
