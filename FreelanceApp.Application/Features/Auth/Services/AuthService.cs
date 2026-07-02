using System;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Auth.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Application.Features.Auth.Services;

public class AuthService(
    IUserRepository userRepository,
    IPasswordHasher passwordHasher,
    IJwtTokenService jwtTokenService,
    IRefreshTokenService refreshTokenService,
    IOptions<JwtSettings> jwtOptions,
    IOtpService otpService,
    IEmailOtpRepository otpRepository, // ⬅️ DbContext ki jagah Repository aa gayi
    ILogger<AuthService> logger) : IAuthService
{
    private readonly JwtSettings _jwtSettings = jwtOptions.Value;

    public async Task<AuthResponseDto> RegisterAsync(RegisterRequestDto dto)
    {
        // ... (Aapka purana RegisterAsync code bilkul theek hai, wahi rahega)
        logger.LogInformation("Register attempt for email: {Email}", dto.Email);
        var normalizedEmail = dto.Email.ToLower().Trim();

        if (await userRepository.EmailExistsAsync(normalizedEmail))
        {
            throw new ConflictException("Email is already registered");
        }

        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = normalizedEmail,
            PasswordHash = passwordHasher.HashPassword(dto.Password),
            FullName = dto.FullName.Trim(),
            Role = dto.Role,
            IsIdentityVerified = false,
            SecurityStamp = Guid.NewGuid(),
            CreatedAt = DateTime.UtcNow
        };

        await userRepository.AddAsync(user);
        await userRepository.SaveChangesAsync();

        await otpService.GenerateAndSendAsync(user.Id, user.Email, user.FullName, OtpPurpose.EmailVerification);

        return await BuildAuthResponseAsync(user);
    }

    public async Task<AuthResponseDto> LoginAsync(LoginRequestDto dto)
    {
        // ... (Aapka purana LoginAsync code wahi rahega)
        var normalizedEmail = dto.Email.ToLower().Trim();
        var user = await userRepository.GetByEmailAsync(normalizedEmail);

        if (user == null || !passwordHasher.VerifyPassword(dto.Password, user.PasswordHash))
        {
            throw new UnauthorizedException("Invalid email or password");
        }

        if (passwordHasher.NeedsRehash(user.PasswordHash))
        {
            user.PasswordHash = passwordHasher.HashPassword(dto.Password);
            await userRepository.SaveChangesAsync();
        }

        return await BuildAuthResponseAsync(user);
    }

    public async Task<AuthResponseDto> RefreshAsync(RefreshTokenRequestDto dto)
    {
        var payload = await refreshTokenService.ValidateAndConsumeAsync(dto.RefreshToken);
        if (payload == null) throw new UnauthorizedException("Invalid or expired refresh token");

        var user = await userRepository.GetByIdAsync(payload.UserId);
        if (user == null) throw new UnauthorizedException("User not found");

        // Stamp mismatch = password reset (or admin revocation) happened after
        // this token was issued. Without this check a stolen refresh token would
        // survive a password reset and mint fresh sessions under the new stamp.
        if (payload.SecurityStamp != user.SecurityStamp)
        {
            logger.LogWarning(
                "Refresh rejected — stale SecurityStamp for user: {UserId} (session revoked)",
                user.Id);
            throw new UnauthorizedException("Session revoked. Please login again.");
        }

        return await BuildAuthResponseAsync(user);
    }

    public async Task LogoutAsync(LogoutRequestDto dto)
    {
        await refreshTokenService.RevokeAsync(dto.RefreshToken);
    }

    private async Task<AuthResponseDto> BuildAuthResponseAsync(User user)
    {
        var accessToken = jwtTokenService.GenerateAccessToken(user);
        var refreshToken = await refreshTokenService.GenerateAsync(user.Id, user.SecurityStamp);

        return new AuthResponseDto
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            TokenType = "Bearer",
            ExpiresAt = DateTime.UtcNow.AddMinutes(_jwtSettings.AccessTokenExpiryMinutes),
            User = new UserResponseDto
            {
                Id = user.Id,
                Email = user.Email,
                FullName = user.FullName,
                Role = user.Role.ToString(),
                IsIdentityVerified = user.IsIdentityVerified,
                CreatedAt = user.CreatedAt
            }
        };
    }

    public async Task VerifyEmailAsync(VerifyEmailRequestDto dto)
    {
        logger.LogInformation("Email verification attempt for: {Email}", dto.Email);
        var normalizedEmail = dto.Email.ToLower().Trim();

        var user = await userRepository.GetByEmailAsync(normalizedEmail);
        if (user == null) throw new UnauthorizedException("Invalid or expired OTP");

        if (user.IsEmailVerified) throw new ConflictException("Email is already verified");

        // 🎯 NAYA TARIQA: Repository use kar rahe hain
        var otp = await otpRepository.GetLatestActiveOtpAsync(user.Id, OtpPurpose.EmailVerification);

        if (otp == null) throw new UnauthorizedException("Invalid or expired OTP");

        if (otp.ExpiresAt < DateTime.UtcNow)
        {
            otp.IsUsed = true;
            await userRepository.SaveChangesAsync(); // Shared transaction
            throw new UnauthorizedException("Invalid or expired OTP");
        }

        if (otp.AttemptCount >= 3)
        {
            otp.IsUsed = true;
            await userRepository.SaveChangesAsync();
            throw new UnauthorizedException("Invalid or expired OTP");
        }

        if (otp.Code != dto.Otp)
        {
            otp.AttemptCount++;
            await userRepository.SaveChangesAsync();
            throw new UnauthorizedException("Invalid or expired OTP");
        }

        // ✅ All checks passed
        otp.IsUsed = true;
        user.IsEmailVerified = true;
        await userRepository.SaveChangesAsync();

        logger.LogInformation("Email verified successfully for: {UserId}", user.Id);
    }

    public async Task ResendOtpAsync(ResendOtpRequestDto dto)
    {
        logger.LogInformation("Resend OTP attempt for: {Email}", dto.Email);

        var normalizedEmail = dto.Email.ToLower().Trim();

        // Layer 1: User existence (SILENT FAILURE — same response either way)
        var user = await userRepository.GetByEmailAsync(normalizedEmail);
        if (user == null)
        {
            logger.LogWarning("Resend OTP — user not found: {Email} (silent fail)", normalizedEmail);
            return;   // ⬅️ Silent success, no error to attacker
        }

        // Layer 2: Already verified — silent ignore (idempotent)
        if (user.IsEmailVerified)
        {
            logger.LogInformation("Resend OTP — user already verified: {UserId} (silent fail)", user.Id);
            return;   // ⬅️ Silent success, no spam emails
        }

        // Layer 3: Cooldown check (60 second throttle)
        var lastOtp = await otpRepository.GetLatestOtpAsync(user.Id, OtpPurpose.EmailVerification);
        if (lastOtp != null)
        {
            var secondsSinceLastOtp = (DateTime.UtcNow - lastOtp.CreatedAt).TotalSeconds;
            const int cooldownSeconds = 60;

            if (secondsSinceLastOtp < cooldownSeconds)
            {
                var waitSeconds = (int)(cooldownSeconds - secondsSinceLastOtp);
                logger.LogWarning(
                    "Resend OTP — cooldown active for user: {UserId} | Wait: {Seconds}s",
                    user.Id, waitSeconds);
                throw new TooManyRequestsException(
                    $"Please wait {waitSeconds} seconds before requesting a new OTP");
            }
        }

        // Layer 4: All checks passed — generate + send
        await otpService.GenerateAndSendAsync(
            userId: user.Id,
            userEmail: user.Email,
            userName: user.FullName,
            purpose: OtpPurpose.EmailVerification);

        logger.LogInformation("OTP resent successfully to: {Email}", user.Email);
    }

    public async Task ForgotPasswordAsync(ForgotPasswordRequestDto dto)
    {
        logger.LogInformation("Forgot password request for: {Email}", dto.Email);

        var normalizedEmail = dto.Email.ToLower().Trim();

        // Layer 1: User existence (SILENT FAILURE — enumeration protection)
        var user = await userRepository.GetByEmailAsync(normalizedEmail);
        if (user == null)
        {
            logger.LogWarning(
                "Forgot password — user not found: {Email} (silent fail)",
                normalizedEmail);
            return;
        }

        // Layer 2: Cooldown check (60-second throttle)
        var lastOtp = await otpRepository.GetLatestOtpAsync(user.Id, OtpPurpose.PasswordReset);
        if (lastOtp != null)
        {
            var secondsSinceLastOtp = (DateTime.UtcNow - lastOtp.CreatedAt).TotalSeconds;
            const int cooldownSeconds = 60;

            if (secondsSinceLastOtp < cooldownSeconds)
            {
                var waitSeconds = (int)(cooldownSeconds - secondsSinceLastOtp);
                logger.LogWarning(
                    "Forgot password — cooldown active for user: {UserId} | Wait: {Seconds}s",
                    user.Id, waitSeconds);
                throw new TooManyRequestsException(
                    $"Please wait {waitSeconds} seconds before requesting another password reset");
            }
        }

        // Layer 3: Generate + send (Password Reset template)
        await otpService.GenerateAndSendAsync(
            userId: user.Id,
            userEmail: user.Email,
            userName: user.FullName,
            purpose: OtpPurpose.PasswordReset);

        logger.LogInformation("Password reset OTP sent to: {Email}", user.Email);
    }

    public async Task ResetPasswordAsync(ResetPasswordRequestDto dto)
    {
        logger.LogInformation("Password reset attempt for: {Email}", dto.Email);

        var normalizedEmail = dto.Email.ToLower().Trim();

        // Check 1: User exists?
        var user = await userRepository.GetByEmailAsync(normalizedEmail);
        if (user == null)
        {
            logger.LogWarning("Password reset failed - user not found: {Email}", normalizedEmail);
            throw new UnauthorizedException("Invalid or expired OTP");
        }

        // Check 2: Get latest active OTP (PasswordReset purpose)
        var otp = await otpRepository.GetLatestActiveOtpAsync(user.Id, OtpPurpose.PasswordReset);
        if (otp == null)
        {
            logger.LogWarning("No active password reset OTP for user: {UserId}", user.Id);
            throw new UnauthorizedException("Invalid or expired OTP");
        }

        // Check 3: Expired?
        if (otp.ExpiresAt < DateTime.UtcNow)
        {
            otp.IsUsed = true;
            await userRepository.SaveChangesAsync();
            logger.LogWarning("OTP expired for user: {UserId}", user.Id);
            throw new UnauthorizedException("Invalid or expired OTP");
        }

        // Check 4: Too many attempts?
        if (otp.AttemptCount >= 3)
        {
            otp.IsUsed = true;
            await userRepository.SaveChangesAsync();
            logger.LogWarning("Max OTP attempts exceeded for user: {UserId}", user.Id);
            throw new UnauthorizedException("Invalid or expired OTP");
        }

        // Check 5: Code match?
        if (otp.Code != dto.Otp)
        {
            otp.AttemptCount++;
            await userRepository.SaveChangesAsync();
            logger.LogWarning("Wrong OTP for user: {UserId} | Attempt: {Count}",
                user.Id, otp.AttemptCount);
            throw new UnauthorizedException("Invalid or expired OTP");
        }

        // ✅ All OTP checks passed — perform password reset

        // 🎯 THE MAGIC: New password + new SecurityStamp = all sessions revoked
        user.PasswordHash = passwordHasher.HashPassword(dto.NewPassword);
        user.SecurityStamp = Guid.NewGuid();   // ⬅️ INSTANT MULTI-DEVICE LOGOUT
        otp.IsUsed = true;

        await userRepository.SaveChangesAsync();

        logger.LogInformation(
            "Password reset successful for user: {UserId} | All sessions revoked",
            user.Id);
    }
}