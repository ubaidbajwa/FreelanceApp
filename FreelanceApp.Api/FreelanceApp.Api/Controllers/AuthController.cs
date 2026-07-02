using FreelanceApp.Application.Features.Auth.DTOs;
using FreelanceApp.Application.Features.Auth.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/auth")]
[EnableRateLimiting("auth")]
public class AuthController(IAuthService authService) : ControllerBase
{
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequestDto dto)
    {
        AuthResponseDto result = await authService.RegisterAsync(dto);
        return CreatedAtAction(nameof(Register), new { id = result.User.Id }, result);
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequestDto dto)
    {
        var result = await authService.LoginAsync(dto);
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
    public async Task<IActionResult> ResendOtp([FromBody] ResendOtpRequestDto dto)
    {
        await authService.ResendOtpAsync(dto);
        return Ok(new { message = "If your email is registered and not verified, an OTP has been sent." });
    }

    [HttpPost("forgot-password")]
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
}