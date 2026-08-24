using FreelanceApp.Application.Features.Auth.DTOs;
using FreelanceApp.Application.Features.Auth.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using System.Security.Claims;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/auth")]
[EnableRateLimiting("auth")]
public class AuthController(IAuthService authService) : ControllerBase
{
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequestDto dto)
    {
        // Email pehle se ho to service 409 Conflict throw karti hai —
        // signup pe hi error dikhta hai, OTP tak intezar nahi.
        await authService.RegisterAsync(dto);
        return Ok(new { message = "Registration successful. A verification code has been sent to your email." });
    }

    [HttpPost("check-email")]
    public async Task<IActionResult> CheckEmail([FromBody] CheckEmailRequestDto dto)
    {
        // Signup step 0 — "Agree & Join" pe instant duplicate check
        var exists = await authService.EmailExistsAsync(dto.Email);
        return Ok(new { exists });
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequestDto dto)
    {
        var result = await authService.LoginAsync(dto);
        return Ok(result);
    }

    [HttpPost("google")]
    public async Task<IActionResult> GoogleLogin([FromBody] GoogleLoginRequest dto, CancellationToken ct)
    {
        // Find-or-create: returning Google user logs in, an existing email gets
        // linked, a new email creates a social account. A bad idToken surfaces
        // as a 401 problem-details (verifier fails closed), never a 500.
        var result = await authService.GoogleLoginAsync(dto, ct);
        return Ok(result);
    }

    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh([FromBody] RefreshTokenRequestDto dto)
    {
        var result = await authService.RefreshAsync(dto);
        return Ok(result);
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout([FromBody] LogoutRequestDto dto)
    {
        await authService.LogoutAsync(dto);
        return NoContent();   // 204 — success, no body
    }

    [HttpPost("verify-email")]
    public async Task<IActionResult> VerifyEmail([FromBody] VerifyEmailRequestDto dto)
    {
        await authService.VerifyEmailAsync(dto);
        return NoContent();
    }

    [HttpPost("resend-otp")]
    [EnableRateLimiting("otp")]   // stricter: 3 per 5 min — email bhejta hai
    public async Task<IActionResult> ResendOtp([FromBody] ResendOtpRequestDto dto)
    {
        await authService.ResendOtpAsync(dto);
        return Ok(new { message = "If your email is registered and not verified, an OTP has been sent." });
    }

    [HttpPost("forgot-password")]
    [EnableRateLimiting("otp")]   // stricter: 3 per 5 min — email bhejta hai
    public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequestDto dto)
    {
        await authService.ForgotPasswordAsync(dto);
        return Ok(new { message = "If your email is registered, a password reset OTP has been sent." });
    }

    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequestDto dto)
    {
        await authService.ResetPasswordAsync(dto);
        return Ok(new { message = "Password reset successful. Please login with your new password." });
    }

    [Authorize]
    [HttpPost("change-password")]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequestDto dto)
    {
        var userIdClaim = User.FindFirst("sub")?.Value
                       ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return Unauthorized(new { message = "Invalid user token" });

        var result = await authService.ChangePasswordAsync(userId, dto);
        return Ok(result);
    }
}