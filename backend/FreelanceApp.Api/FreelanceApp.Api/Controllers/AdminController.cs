using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
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
    public async Task<IActionResult> CreateAdmin(
        [FromHeader(Name = "X-Admin-Secret")] string? adminSecret,
        [FromBody] CreateAdminRequest request)
    {
        if (string.IsNullOrWhiteSpace(adminSecret) ||
            adminSecret != adminOptions.Value.CreationSecret)
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
}

public class CreateAdminRequest
{
    public string Email { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
}
