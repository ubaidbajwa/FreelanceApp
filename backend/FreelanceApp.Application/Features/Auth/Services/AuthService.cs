using System;
using FreelanceApp.Application.Common.Capabilities;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Auth.DTOs;
using FreelanceApp.Application.Features.Profiles;
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
    IProfileRepository profileRepository, // capabilities compute karne ke liye (CanFreelance)
    ICaptchaVerifier captchaVerifier,
    IGoogleTokenVerifier googleTokenVerifier,
    ILogger<AuthService> logger) : IAuthService
{
    private readonly JwtSettings _jwtSettings = jwtOptions.Value;

    public async Task RegisterAsync(RegisterRequestDto dto)
    {
        logger.LogInformation("Register attempt for email: {Email}", dto.Email);

        // Captcha check runs BEFORE any DB lookup or user creation so bots
        // can't even probe email-existence or spend our resources. Verifier
        // fails closed (returns false) on network errors.
        if (!await captchaVerifier.VerifyAsync(dto.CaptchaToken, CancellationToken.None))
        {
            logger.LogWarning("Register — captcha verification failed for email: {Email}", dto.Email);
            throw new ValidationException("Captcha verification failed");
        }

        var normalizedEmail = dto.Email.ToLower().Trim();

        // Product decision (2026-07): duplicate email ka error signup pe hi
        // dikhana hai (LinkedIn-style UX). Enumeration ka bachao ab sirf rate
        // limiting se hai — /check-email endpoint bhi yehi reveal karta hai.
        if (await userRepository.EmailExistsAsync(normalizedEmail))
        {
            logger.LogWarning("Register — email already exists: {Email}", normalizedEmail);
            throw new ConflictException("An account with this email already exists. Try signing in instead.");
        }

        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = normalizedEmail,
            PasswordHash = passwordHasher.HashPassword(dto.Password),
            FullName = dto.FullName.Trim(),
            PrimaryRole = dto.Role, // request field "role" → primary role (default experience)
            IsIdentityVerified = false,
            SecurityStamp = Guid.NewGuid(),
            CreatedAt = DateTime.UtcNow
        };

        await userRepository.AddAsync(user);
        await userRepository.SaveChangesAsync();

        // No tokens issued here — the user gets them from login after verifying their
        // email. Handing out tokens at register would let unverified accounts bypass
        // the email-verification gate on login.
        //
        // GenerateAndSendAsync persists the OTP row to DB, then enqueues the email
        // (EmailBackgroundService sends it). No SMTP wait here — the response returns
        // as soon as the OTP is committed.
        await otpService.GenerateAndSendAsync(user.Id, user.Email, user.FullName, OtpPurpose.EmailVerification);
    }

    // Signup step 0 ka instant check — "Agree & Join" pe hi pata chal jaye
    // ke email pehle se registered hai (OTP tak intezar nahi)
    public async Task<bool> EmailExistsAsync(string email)
    {
        var normalizedEmail = email.ToLower().Trim();
        return await userRepository.EmailExistsAsync(normalizedEmail);
    }

    public async Task<AuthResponseDto> LoginAsync(LoginRequestDto dto)
    {
        // ... (Aapka purana LoginAsync code wahi rahega)
        var normalizedEmail = dto.Email.ToLower().Trim();
        var user = await userRepository.GetByEmailAsync(normalizedEmail);

        if (user == null)
        {
            throw new UnauthorizedException("Invalid email or password");
        }

        // Social-login accounts (Google/MS/Apple) have no PasswordHash. Guard
        // BEFORE BCrypt.Verify — a null hash makes it throw (→ 500). Point the
        // user at the right door instead of a generic failure.
        if (user.PasswordHash is null)
        {
            logger.LogWarning(
                "Login blocked — password login attempted on {Provider} account: {UserId}",
                user.Provider, user.Id);
            throw new UnauthorizedException(
                $"This account uses {user.Provider} Sign-In. Please continue with {user.Provider}.");
        }

        if (!passwordHasher.VerifyPassword(dto.Password, user.PasswordHash))
        {
            throw new UnauthorizedException("Invalid email or password");
        }

        if (passwordHasher.NeedsRehash(user.PasswordHash))
        {
            user.PasswordHash = passwordHasher.HashPassword(dto.Password);
            await userRepository.SaveChangesAsync();
        }

        // Checked AFTER password verification on purpose: a wrong-password
        // attacker sees the same generic 401 and can't use this message to
        // probe whether an email is registered.
        if (!user.IsEmailVerified)
        {
            logger.LogWarning("Login blocked — email not verified for user: {UserId}", user.Id);
            throw new ForbiddenException(
                "Please verify your email before logging in. Use resend-otp to get a new code.");
        }

        return await BuildAuthResponseAsync(user);
    }

    public async Task<AuthResponseDto> GoogleLoginAsync(GoogleLoginRequest request, CancellationToken ct = default)
    {
        logger.LogInformation("Google login attempt");

        // Verifier fails closed: a bad signature, wrong audience, expired token,
        // or even a network error fetching Google's certs all return null. We map
        // that to a 401 (via UnauthorizedException) so a garbage token can never
        // surface as a 500.
        var payload = await googleTokenVerifier.VerifyAsync(request.IdToken, ct);
        if (payload is null)
        {
            logger.LogWarning("Google login — token verification failed");
            throw new UnauthorizedException("Invalid Google token");
        }

        // Google itself says this email isn't verified — don't trust it for
        // matching or account creation. Otherwise someone could sign in with an
        // unverified Google email that happens to match a real user and hijack it.
        if (!payload.EmailVerified)
        {
            logger.LogWarning("Google login — email not verified by Google for subject: {Subject}", payload.Subject);
            throw new UnauthorizedException("Your Google email address is not verified.");
        }

        var normalizedEmail = payload.Email.ToLower().Trim();

        // 1) Returning Google user — matched on Google's stable subject id, which
        //    never changes even if the user later changes their email.
        var user = await userRepository.GetByExternalIdAsync(AuthProvider.Google, payload.Subject);

        // 2) First Google login, but this email already has an account — link the
        //    Google identity to it instead of creating a duplicate. The password
        //    hash (if any) is kept, so an existing local account can still use both.
        if (user is null)
        {
            user = await userRepository.GetByEmailAsync(normalizedEmail);
            if (user is not null)
            {
                user.Provider = AuthProvider.Google;
                user.ExternalId = payload.Subject;
                user.IsEmailVerified = true; // Google already verified ownership
                await userRepository.SaveChangesAsync();
                logger.LogInformation("Google login — linked Google identity to existing user: {UserId}", user.Id);
            }
        }

        // 3) Brand-new user — create a social-only account (no password hash).
        if (user is null)
        {
            user = new User
            {
                Id = Guid.NewGuid(),
                Email = normalizedEmail,
                PasswordHash = null, // social account — no local password
                FullName = string.IsNullOrWhiteSpace(payload.FullName)
                    ? normalizedEmail
                    : payload.FullName.Trim(),
                Provider = AuthProvider.Google,
                ExternalId = payload.Subject,
                PrimaryRole = UserRole.Freelancer,
                IsIdentityVerified = false,
                IsEmailVerified = true, // Google already verified the email
                SecurityStamp = Guid.NewGuid(),
                CreatedAt = DateTime.UtcNow
            };

            await userRepository.AddAsync(user);
            await userRepository.SaveChangesAsync();
            logger.LogInformation("Google login — created new social user: {UserId}", user.Id);
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

        // Capabilities computed, never stored — CanFreelance needs profile completion.
        var profile = await profileRepository.GetByUserIdAsync(user.Id);
        var capabilities = UserCapabilities.Evaluate(
            profileExists: profile != null,
            completionPercent: profile != null ? ProfileCompletionCalculator.Calculate(profile) : 0);

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
                Role = user.PrimaryRole.ToString(), // field name unchanged; value = primary role
                IsIdentityVerified = user.IsIdentityVerified,
                CreatedAt = user.CreatedAt,
                Capabilities = capabilities
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

    public async Task<AuthResponseDto> ChangePasswordAsync(Guid userId, ChangePasswordRequestDto dto)
    {
        logger.LogInformation("Change password attempt for user: {UserId}", userId);

        var user = await userRepository.GetByIdAsync(userId);
        if (user == null) throw new UnauthorizedException("User not found");

        // Social-login accounts have no local password to verify or change.
        if (user.PasswordHash is null)
        {
            logger.LogWarning(
                "Change password blocked — {Provider} account has no local password: {UserId}",
                user.Provider, userId);
            throw new ConflictException(
                $"This account uses {user.Provider} Sign-In and has no password to change.");
        }

        // User is already authenticated (JWT), but re-verifying the current
        // password blocks an attacker holding a stolen access token from
        // locking the real owner out of their account.
        if (!passwordHasher.VerifyPassword(dto.CurrentPassword, user.PasswordHash))
        {
            logger.LogWarning("Change password failed — wrong current password for user: {UserId}", userId);
            throw new UnauthorizedException("Current password is incorrect");
        }

        if (dto.CurrentPassword == dto.NewPassword)
        {
            throw new ConflictException("New password must be different from the current password");
        }

        // New password + new SecurityStamp = all other sessions revoked.
        // Middleware checks the stamp on every request, so the caller's own
        // tokens die too — that's why we return a fresh token pair below,
        // keeping the current device logged in.
        user.PasswordHash = passwordHasher.HashPassword(dto.NewPassword);
        user.SecurityStamp = Guid.NewGuid();

        await userRepository.SaveChangesAsync();

        logger.LogInformation(
            "Password changed successfully for user: {UserId} | Other sessions revoked",
            user.Id);

        return await BuildAuthResponseAsync(user);
    }
}