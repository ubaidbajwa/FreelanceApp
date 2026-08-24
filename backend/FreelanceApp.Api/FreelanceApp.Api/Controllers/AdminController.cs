using System.Security.Cryptography;
using System.Text;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/admin")]
public class AdminController(
    IAdminUserService adminUserService,
    IOptions<AdminSettings> adminOptions) : ControllerBase
{
    [HttpPost("create-admin")]
    [AllowAnonymous]
    [EnableRateLimiting("otp")]   // 3 per 5 min per IP — header-secret brute-force block
    public async Task<IActionResult> CreateAdmin(
        [FromHeader(Name = "X-Admin-Secret")] string? adminSecret,
        [FromBody] CreateAdminRequest request)
    {
        if (!IsValidAdminSecret(adminSecret))
        {
            return Unauthorized(new { message = "Invalid or missing admin secret." });
        }

        var adminId = await adminUserService.CreateAdminAsync(
            request.Email,
            request.Password,
            request.FullName);

        return Created(string.Empty, new
        {
            adminId,
            message = "Admin user created successfully. Use /api/auth/login to sign in."
        });
    }

    // Constant-time compare — plain `!=` leaks match length via timing, letting an
    // attacker recover the secret byte-by-byte. FixedTimeEquals removes that oracle.
    // An empty configured secret is treated as "disabled" (always rejects).
    private bool IsValidAdminSecret(string? provided)
    {
        var expected = adminOptions.Value.CreationSecret;
        if (string.IsNullOrEmpty(provided) || string.IsNullOrEmpty(expected))
            return false;

        var providedBytes = Encoding.UTF8.GetBytes(provided);
        var expectedBytes = Encoding.UTF8.GetBytes(expected);

        return CryptographicOperations.FixedTimeEquals(providedBytes, expectedBytes);
    }
}

public class CreateAdminRequest
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
}
