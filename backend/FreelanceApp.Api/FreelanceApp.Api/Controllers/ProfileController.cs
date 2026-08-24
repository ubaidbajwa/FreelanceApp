using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Profiles.DTOs;
using FreelanceApp.Application.Features.Profiles.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using System.Security.Claims;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/profile")]
[Authorize]
public class ProfileController(IProfileService profileService) : ControllerBase
{
    private const long MaxPhotoSizeBytes = 5 * 1024 * 1024;   // 5 MB

    private static readonly string[] AllowedPhotoExtensions = [".jpg", ".jpeg", ".png", ".webp"];
    private static readonly string[] AllowedPhotoContentTypes = ["image/jpeg", "image/png", "image/webp"];

    // ===== PROFILE =====

    [HttpGet("me")]
    public async Task<IActionResult> GetMyProfile(CancellationToken ct)
    {
        var profile = await profileService.GetMyProfileAsync(GetUserId(), ct);
        return Ok(profile);
    }

    [HttpPut("me")]
    public async Task<IActionResult> UpdateMyProfile(
        [FromBody] UpdateProfileRequestDto dto, CancellationToken ct)
    {
        var profile = await profileService.UpdateMyProfileAsync(GetUserId(), dto, ct);
        return Ok(profile);
    }

    // ===== EXPERIENCES =====

    [HttpPost("me/experiences")]
    public async Task<IActionResult> AddExperience(
        [FromBody] ExperienceRequestDto dto, CancellationToken ct)
    {
        var experience = await profileService.AddExperienceAsync(GetUserId(), dto, ct);
        return Ok(experience);
    }

    [HttpPut("me/experiences/{id:guid}")]
    public async Task<IActionResult> UpdateExperience(
        Guid id, [FromBody] ExperienceRequestDto dto, CancellationToken ct)
    {
        var experience = await profileService.UpdateExperienceAsync(GetUserId(), id, dto, ct);
        return Ok(experience);
    }

    [HttpDelete("me/experiences/{id:guid}")]
    public async Task<IActionResult> DeleteExperience(Guid id, CancellationToken ct)
    {
        await profileService.DeleteExperienceAsync(GetUserId(), id, ct);
        return NoContent();
    }

    // ===== USERNAME =====

    [HttpGet("username-available")]
    [EnableRateLimiting("auth")]
    public async Task<IActionResult> IsUsernameAvailable(
        [FromQuery] string username, CancellationToken ct)
    {
        var available = await profileService.IsUsernameAvailableAsync(GetUserId(), username, ct);
        return Ok(new { available });
    }

    [HttpPut("username")]
    public async Task<IActionResult> ClaimUsername(
        [FromBody] ClaimUsernameRequestDto dto, CancellationToken ct)
    {
        var profile = await profileService.ClaimUsernameAsync(GetUserId(), dto.Username, ct);
        return Ok(profile);
    }

    // ===== PHOTO =====

    [HttpPost("me/photo")]
    public async Task<IActionResult> UploadPhoto(IFormFile photo, CancellationToken ct)
    {
        if (photo == null || photo.Length == 0)
            throw new ValidationException("Photo file is required.");

        if (photo.Length > MaxPhotoSizeBytes)
            throw new ValidationException("Photo exceeds the 5 MB limit.");

        var extension = Path.GetExtension(photo.FileName).ToLowerInvariant();
        if (!AllowedPhotoExtensions.Contains(extension) ||
            !AllowedPhotoContentTypes.Contains(photo.ContentType.ToLowerInvariant()))
        {
            throw new ValidationException("Only JPG, PNG and WEBP images are allowed.");
        }

        var url = await profileService.UploadPhotoAsync(
            GetUserId(), photo.OpenReadStream(), photo.FileName, ct);

        return Ok(new { profilePhotoUrl = url });
    }

    // ===== HELPERS =====

    private Guid GetUserId()
    {
        var userIdClaim = User.FindFirst("sub")?.Value
                       ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            throw new UnauthorizedException("Invalid user token");

        return userId;
    }
}
