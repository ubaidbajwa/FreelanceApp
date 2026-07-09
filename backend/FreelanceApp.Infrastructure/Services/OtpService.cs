using System.Security.Cryptography;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Email;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace FreelanceApp.Infrastructure.Services;

public class OtpService : IOtpService
{
    private const int OtpExpiryMinutes = 10;

    private readonly AppDbContext _db;
    private readonly IEmailService _emailService;
    private readonly ILogger<OtpService> _logger;

    public OtpService(
        AppDbContext db,
        IEmailService emailService,
        ILogger<OtpService> logger)
    {
        _db = db;
        _emailService = emailService;
        _logger = logger;
    }

    public async Task GenerateAndSendAsync(
        Guid userId,
        string userEmail,
        string userName,
        OtpPurpose purpose,
        CancellationToken ct = default)
    {
        // Step 1: Invalidate any existing unused OTPs for this user+purpose
        await InvalidateOldOtpsAsync(userId, purpose, ct);

        // Step 2: Generate new 6-digit code (cryptographically secure)
        var code = GenerateSecureCode();

        // Step 3: Save to database
        var otp = new EmailOtp
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Code = code,
            Purpose = purpose,
            ExpiresAt = DateTime.UtcNow.AddMinutes(OtpExpiryMinutes),
            IsUsed = false,
            AttemptCount = 0,
            CreatedAt = DateTime.UtcNow
        };

        _db.EmailOtps.Add(otp);
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation(
            "OTP generated for user {UserId} | Purpose: {Purpose}",
            userId, purpose);

        // Step 4: Send email
        var subject = purpose == OtpPurpose.EmailVerification
            ? "Verify your email — Freelance Job Finder"
            : "Reset your password — Freelance Job Finder";

        // ⬇️ UPDATED — purpose ke hisaab se template
        var htmlBody = purpose == OtpPurpose.EmailVerification
            ? EmailTemplates.EmailVerificationOtp(userName, code, OtpExpiryMinutes)
            : EmailTemplates.PasswordResetOtp(userName, code, OtpExpiryMinutes);

        await _emailService.SendAsync(
            toEmail: userEmail,
            toName: userName,
            subject: subject,
            htmlBody: htmlBody,
            ct: ct);
    }

    private async Task InvalidateOldOtpsAsync(
        Guid userId,
        OtpPurpose purpose,
        CancellationToken ct)
    {
        await _db.EmailOtps
            .Where(o => o.UserId == userId
                     && o.Purpose == purpose
                     && !o.IsUsed)
            .ExecuteUpdateAsync(
                setters => setters.SetProperty(o => o.IsUsed, true),
                ct);
    }

    private static string GenerateSecureCode()
    {
        // Cryptographically secure 6-digit code (100000 - 999999)
        var number = RandomNumberGenerator.GetInt32(100000, 1000000);
        return number.ToString();
    }
}