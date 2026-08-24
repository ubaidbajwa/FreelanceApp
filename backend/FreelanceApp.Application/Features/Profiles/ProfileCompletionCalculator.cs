using FreelanceApp.Domain.Entities;

namespace FreelanceApp.Application.Features.Profiles;

/// <summary>
/// Single source of truth for profile completion %. Used both for the profile response
/// and for deriving the CanFreelance capability, so the two never drift apart.
/// Weights: photo 10, displayName 10, headline 10, bio 15, skills 20,
///          rate 10, location+preference 10, >=1 experience 15  (total 100).
/// </summary>
public static class ProfileCompletionCalculator
{
    public static int Calculate(Profile profile)
    {
        int percent = 0;

        if (!string.IsNullOrWhiteSpace(profile.ProfilePhotoUrl)) percent += 10;
        if (!string.IsNullOrWhiteSpace(profile.DisplayName)) percent += 10;
        if (!string.IsNullOrWhiteSpace(profile.Headline)) percent += 10;
        if (!string.IsNullOrWhiteSpace(profile.Bio)) percent += 15;
        if (profile.Skills.Count > 0) percent += 20;
        if (profile.HourlyRate is > 0) percent += 10;

        // Location/preference — teeno set hon tab 10%
        if (!string.IsNullOrWhiteSpace(profile.Country) &&
            !string.IsNullOrWhiteSpace(profile.City) &&
            profile.WorkPreference != null)
            percent += 10;

        if (profile.Experiences.Count > 0) percent += 15;

        return percent;
    }
}
