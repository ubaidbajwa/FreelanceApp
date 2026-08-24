using System.Text.RegularExpressions;
using FreelanceApp.Application.Common.Capabilities;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Profiles.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using Microsoft.Extensions.Logging;

namespace FreelanceApp.Application.Features.Profiles.Services;

public class ProfileService(
    IProfileRepository profileRepository,
    IUserRepository userRepository,
    IImageStorageService imageStorage,
    ILogger<ProfileService> logger) : IProfileService
{
    private const string PhotoFolderName = "profile-photos";

    // 3-30 chars, lowercase letters/digits/underscore, letter se start
    private static readonly Regex UsernameRegex = new(@"^[a-z][a-z0-9_]{2,29}$", RegexOptions.Compiled);

    // ===== GET (get-or-create) =====

    public async Task<ProfileResponseDto> GetMyProfileAsync(Guid userId, CancellationToken ct = default)
    {
        var profile = await GetOrCreateProfileAsync(userId);
        return MapToDto(profile);
    }

    // ===== PARTIAL UPDATE =====

    public async Task<ProfileResponseDto> UpdateMyProfileAsync(
        Guid userId, UpdateProfileRequestDto dto, CancellationToken ct = default)
    {
        var profile = await GetOrCreateProfileAsync(userId);

        // Sirf non-null fields apply — PATCH semantics on PUT (contract-documented)
        if (dto.DisplayName != null) profile.DisplayName = dto.DisplayName.Trim();
        if (dto.Headline != null) profile.Headline = dto.Headline.Trim();
        if (dto.Bio != null) profile.Bio = dto.Bio.Trim();
        if (dto.HourlyRate != null) profile.HourlyRate = dto.HourlyRate;
        if (dto.Availability != null) profile.Availability = dto.Availability;
        if (dto.WorkPreference != null) profile.WorkPreference = dto.WorkPreference;
        if (dto.AvailabilityStatus != null) profile.AvailabilityStatus = dto.AvailabilityStatus;
        if (dto.ClientType != null) profile.ClientType = dto.ClientType;
        if (dto.BusinessName != null) profile.BusinessName = dto.BusinessName.Trim();
        if (dto.Country != null) profile.Country = dto.Country.Trim();
        if (dto.City != null) profile.City = dto.City.Trim();
        if (dto.Skills != null)
            profile.Skills = dto.Skills
                .Select(s => s.Trim())
                .Where(s => s.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

        if (dto.DesiredJobTitles != null)
            profile.DesiredJobTitles = dto.DesiredJobTitles
                .Select(s => s.Trim())
                .Where(s => s.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

        if (dto.DesiredJobLocations != null)
            profile.DesiredJobLocations = dto.DesiredJobLocations
                .Select(s => s.Trim())
                .Where(s => s.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

        if (dto.HiringInterests != null)
            profile.HiringInterests = dto.HiringInterests
                .Select(s => s.Trim())
                .Where(s => s.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

        if (dto.HiringType != null) profile.HiringType = dto.HiringType;
        if (dto.InvitePolicy != null) profile.InvitePolicy = dto.InvitePolicy;

        profile.UpdatedAt = DateTime.UtcNow;
        await profileRepository.SaveChangesAsync();

        logger.LogInformation("Profile updated for user: {UserId}", userId);
        return MapToDto(profile);
    }

    // ===== EXPERIENCES =====

    public async Task<ExperienceResponseDto> AddExperienceAsync(
        Guid userId, ExperienceRequestDto dto, CancellationToken ct = default)
    {
        var profile = await GetOrCreateProfileAsync(userId);

        var experience = new Experience
        {
            Id = Guid.NewGuid(),
            ProfileId = profile.Id,
            Title = dto.Title.Trim(),
            Company = dto.Company.Trim(),
            StartDate = dto.StartDate,
            EndDate = dto.EndDate,
            Description = dto.Description?.Trim()
        };

        await profileRepository.AddExperienceAsync(experience);
        profile.UpdatedAt = DateTime.UtcNow;
        await profileRepository.SaveChangesAsync();

        logger.LogInformation("Experience added | User: {UserId} | Experience: {ExperienceId}", userId, experience.Id);
        return MapToDto(experience);
    }

    public async Task<ExperienceResponseDto> UpdateExperienceAsync(
        Guid userId, Guid experienceId, ExperienceRequestDto dto, CancellationToken ct = default)
    {
        var experience = await GetOwnedExperienceAsync(userId, experienceId);

        experience.Title = dto.Title.Trim();
        experience.Company = dto.Company.Trim();
        experience.StartDate = dto.StartDate;
        experience.EndDate = dto.EndDate;
        experience.Description = dto.Description?.Trim();

        await profileRepository.SaveChangesAsync();

        logger.LogInformation("Experience updated | User: {UserId} | Experience: {ExperienceId}", userId, experienceId);
        return MapToDto(experience);
    }

    public async Task DeleteExperienceAsync(Guid userId, Guid experienceId, CancellationToken ct = default)
    {
        var experience = await GetOwnedExperienceAsync(userId, experienceId);

        profileRepository.RemoveExperience(experience);
        await profileRepository.SaveChangesAsync();

        logger.LogInformation("Experience deleted | User: {UserId} | Experience: {ExperienceId}", userId, experienceId);
    }

    // Ownership check — doosre user ki experience pe bhi 404 (info leak nahi karte)
    private async Task<Experience> GetOwnedExperienceAsync(Guid userId, Guid experienceId)
    {
        var profile = await profileRepository.GetByUserIdAsync(userId);
        var experience = await profileRepository.GetExperienceByIdAsync(experienceId);

        if (profile == null || experience == null || experience.ProfileId != profile.Id)
            throw new NotFoundException("Experience not found.");

        return experience;
    }

    // ===== USERNAME =====

    public async Task<bool> IsUsernameAvailableAsync(Guid userId, string username, CancellationToken ct = default)
    {
        var normalized = NormalizeAndValidateUsername(username);
        // Apna current username khud ke liye "available" hai
        return !await profileRepository.UsernameExistsAsync(normalized, excludeUserId: userId);
    }

    public async Task<ProfileResponseDto> ClaimUsernameAsync(Guid userId, string username, CancellationToken ct = default)
    {
        var normalized = NormalizeAndValidateUsername(username);
        var profile = await GetOrCreateProfileAsync(userId);

        if (profile.Username == normalized)
            return MapToDto(profile);   // same username dobara — idempotent success

        if (await profileRepository.UsernameExistsAsync(normalized, excludeUserId: userId))
            throw new ConflictException("Username already taken.");

        profile.Username = normalized;
        profile.UpdatedAt = DateTime.UtcNow;

        // Race condition: check-then-set ke beech koi aur claim kar le to unique index
        // violation aati hai — repository usay ConflictException mein translate karta hai
        await profileRepository.SaveChangesAsync();

        logger.LogInformation("Username claimed | User: {UserId} | Username: {Username}", userId, normalized);
        return MapToDto(profile);
    }

    private static string NormalizeAndValidateUsername(string username)
    {
        var normalized = (username ?? string.Empty).Trim().ToLowerInvariant();

        if (!UsernameRegex.IsMatch(normalized))
            throw new ValidationException(
                "Username must be 3-30 characters, lowercase letters/digits/underscore only, and start with a letter.");

        return normalized;
    }

    // ===== PHOTO =====

    public async Task<string> UploadPhotoAsync(
        Guid userId, Stream fileStream, string fileName, CancellationToken ct = default)
    {
        var profile = await GetOrCreateProfileAsync(userId);
        var oldPhotoUrl = profile.ProfilePhotoUrl;

        var url = await imageStorage.UploadAsync(
            fileStream,
            $"{Guid.NewGuid()}_profile_{fileName}",
            PhotoFolderName, ct);

        profile.ProfilePhotoUrl = url;
        profile.UpdatedAt = DateTime.UtcNow;
        await profileRepository.SaveChangesAsync();

        // Purani photo cleanup — DB commit ke BAAD, best-effort (fail ho to bhi upload success)
        if (!string.IsNullOrEmpty(oldPhotoUrl))
            await imageStorage.DeleteByUrlAsync(oldPhotoUrl, ct);

        logger.LogInformation("Profile photo updated for user: {UserId}", userId);
        return url;
    }

    // ===== GET-OR-CREATE =====

    private async Task<Profile> GetOrCreateProfileAsync(Guid userId)
    {
        var profile = await profileRepository.GetByUserIdAsync(userId);
        if (profile != null)
            return profile;

        var user = await userRepository.GetByIdAsync(userId);
        if (user == null)
            throw new UnauthorizedException("User not found.");

        profile = new Profile
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            DisplayName = user.FullName,    // prefill — user baad mein badal sakta hai
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        await profileRepository.AddAsync(profile);
        await profileRepository.SaveChangesAsync();

        logger.LogInformation("Empty profile created for user: {UserId}", userId);
        return profile;
    }

    // ===== MAPPING =====
    // Completion % ab shared ProfileCompletionCalculator se aata hai (capabilities bhi
    // wahi number use karti hain — do jagah formula duplicate nahi hota).

    private static ProfileResponseDto MapToDto(Profile profile)
    {
        var percent = ProfileCompletionCalculator.Calculate(profile);
        return new()
        {
            Id = profile.Id,
            UserId = profile.UserId,
            DisplayName = profile.DisplayName,
            Headline = profile.Headline,
            Bio = profile.Bio,
            ProfilePhotoUrl = profile.ProfilePhotoUrl,
            HourlyRate = profile.HourlyRate,
            Availability = profile.Availability,
            WorkPreference = profile.WorkPreference,
            AvailabilityStatus = profile.AvailabilityStatus,
            ClientType = profile.ClientType,
            BusinessName = profile.BusinessName,
            Country = profile.Country,
            City = profile.City,
            Username = profile.Username,
            Skills = profile.Skills,
            DesiredJobTitles = profile.DesiredJobTitles,
            DesiredJobLocations = profile.DesiredJobLocations,
            HiringInterests = profile.HiringInterests,
            HiringType = profile.HiringType,
            InvitePolicy = profile.InvitePolicy,
            ProfileCompletionPercent = percent,
            Capabilities = UserCapabilities.Evaluate(profileExists: true, completionPercent: percent),
            Experiences = profile.Experiences
                .OrderByDescending(e => e.EndDate == null)      // current positions pehle
                .ThenByDescending(e => e.StartDate)
                .Select(MapToDto)
                .ToList(),
            CreatedAt = profile.CreatedAt,
            UpdatedAt = profile.UpdatedAt
        };
    }

    private static ExperienceResponseDto MapToDto(Experience experience) => new()
    {
        Id = experience.Id,
        Title = experience.Title,
        Company = experience.Company,
        StartDate = experience.StartDate,
        EndDate = experience.EndDate,
        Description = experience.Description
    };
}
