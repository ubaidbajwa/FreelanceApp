using FreelanceApp.Application.Features.Profiles.DTOs;

namespace FreelanceApp.Application.Features.Profiles.Services;

public interface IProfileService
{
    Task<ProfileResponseDto> GetMyProfileAsync(Guid userId, CancellationToken ct = default);
    Task<ProfileResponseDto> UpdateMyProfileAsync(Guid userId, UpdateProfileRequestDto dto, CancellationToken ct = default);

    Task<ExperienceResponseDto> AddExperienceAsync(Guid userId, ExperienceRequestDto dto, CancellationToken ct = default);
    Task<ExperienceResponseDto> UpdateExperienceAsync(Guid userId, Guid experienceId, ExperienceRequestDto dto, CancellationToken ct = default);
    Task DeleteExperienceAsync(Guid userId, Guid experienceId, CancellationToken ct = default);

    Task<bool> IsUsernameAvailableAsync(Guid userId, string username, CancellationToken ct = default);
    Task<ProfileResponseDto> ClaimUsernameAsync(Guid userId, string username, CancellationToken ct = default);

    Task<string> UploadPhotoAsync(Guid userId, Stream fileStream, string fileName, CancellationToken ct = default);
}
