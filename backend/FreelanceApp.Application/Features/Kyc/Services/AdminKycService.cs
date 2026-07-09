using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Kyc.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging;

namespace FreelanceApp.Application.Features.Kyc.Services;

public class AdminKycService(
    IKycRepository kycRepository,
    IUserRepository userRepository,
    ILogger<AdminKycService> logger) : IAdminKycService
{
    public async Task<List<AdminKycCaseDto>> GetPendingCasesAsync()
    {
        var cases = await kycRepository.GetPendingReviewAsync();

        return cases.Select(v => new AdminKycCaseDto
        {
            VerificationId = v.Id,
            UserId = v.UserId,
            UserEmail = v.User?.Email ?? string.Empty,
            UserFullName = v.User?.FullName ?? string.Empty,
            DocumentType = v.DocumentType,
            FrontImageUrl = v.FrontImageUrl,
            BackImageUrl = v.BackImageUrl,
            SelfieImageUrl = v.SelfieImageUrl,
            ExtractedFullName = v.ExtractedFullName,
            ExtractedDocumentNumber = v.ExtractedDocumentNumber,
            ExtractedDateOfBirth = v.ExtractedDateOfBirth,
            FaceMatchScore = v.FaceMatchScore,
            AttemptCount = v.AttemptCount,
            SubmittedAt = v.CreatedAt
        }).ToList();
    }

    public async Task ApproveAsync(Guid verificationId)
    {
        var verification = await kycRepository.GetByIdAsync(verificationId)
            ?? throw new NotFoundException("KYC verification not found.");

        if (verification.Status != KycStatus.UnderReview)
            throw new ConflictException($"Cannot approve a verification with status '{verification.Status}'.");

        verification.Status = KycStatus.Verified;
        verification.VerifiedAt = DateTime.UtcNow;
        verification.RejectionReason = null;

        var user = await userRepository.GetByIdAsync(verification.UserId)
            ?? throw new NotFoundException("User not found.");

        user.IsIdentityVerified = true;
        user.SecurityStamp = Guid.NewGuid();  // invalidates all existing JWT tokens

        await kycRepository.SaveChangesAsync();

        logger.LogInformation("Admin approved KYC | VerificationId: {VerificationId} | UserId: {UserId}",
            verificationId, verification.UserId);
    }

    public async Task RejectAsync(Guid verificationId, string reason)
    {
        var verification = await kycRepository.GetByIdAsync(verificationId)
            ?? throw new NotFoundException("KYC verification not found.");

        if (verification.Status != KycStatus.UnderReview)
            throw new ConflictException($"Cannot reject a verification with status '{verification.Status}'.");

        verification.Status = KycStatus.Failed;
        verification.RejectionReason = reason;

        await kycRepository.SaveChangesAsync();

        logger.LogInformation("Admin rejected KYC | VerificationId: {VerificationId} | UserId: {UserId} | Reason: {Reason}",
            verificationId, verification.UserId, reason);
    }
}
