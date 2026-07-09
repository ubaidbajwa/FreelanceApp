using FreelanceApp.Api.Models;
using FreelanceApp.Application.Features.Kyc.DTOs;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/kyc")]
[Authorize]
public class KycController(IKycService kycService) : ControllerBase
{
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;

    [HttpPost("upload")]
    public async Task<IActionResult> UploadDocuments(
        [FromForm] KycUploadApiRequest apiRequest,
        CancellationToken ct)
    {
        var userIdClaim = User.FindFirst("sub")?.Value
               ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { message = "Invalid user token" });

        if (apiRequest.FrontImage.Length > MaxFileSizeBytes ||
            apiRequest.SelfieImage.Length > MaxFileSizeBytes ||
            (apiRequest.BackImage?.Length > MaxFileSizeBytes))
        {
            return BadRequest(new { message = "Image exceeds 10 MB limit" });
        }

        if (apiRequest.FrontImage.Length == 0 || apiRequest.SelfieImage.Length == 0)
            return BadRequest(new { message = "Image files cannot be empty" });

        var request = new KycUploadRequest
        {
            DocumentType = apiRequest.DocumentType,
            FrontImageStream = apiRequest.FrontImage.OpenReadStream(),
            FrontImageFileName = apiRequest.FrontImage.FileName,
            SelfieImageStream = apiRequest.SelfieImage.OpenReadStream(),
            SelfieImageFileName = apiRequest.SelfieImage.FileName,
            BackImageStream = apiRequest.BackImage?.OpenReadStream(),
            BackImageFileName = apiRequest.BackImage?.FileName
        };

        var kycId = await kycService.UploadDocumentsAsync(userId, request, ct);

        return Ok(new
        {
            kycId,
            message = "KYC documents uploaded successfully. Verification under review."
        });
    }

    // ==========================================
    // NEW STATUS ENDPOINT ADDED HERE
    // ==========================================
    [HttpGet("status")]
    public async Task<IActionResult> GetStatus()
    {
        var userIdClaim = User.FindFirst("sub")?.Value
                       ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { message = "Invalid user token" });

        var status = await kycService.GetStatusAsync(userId);
        return Ok(status);
    }
}