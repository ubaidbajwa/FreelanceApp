using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Kyc.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Application.Features.Kyc.Services;

public class KycService(
    IUserRepository userRepository,
    IImageStorageService imageStorage,
    IKycRepository kycRepository,
    IOcrService ocrService,
    IFaceMatchService faceMatchService,
    IOptions<AwsRekognitionSettings> rekognitionOptions,
    ILogger<KycService> logger) : IKycService
{
    private const string KycFolderName = "kyc-documents";
    private const int MaxAttempts = 3;

    private readonly AwsRekognitionSettings _rekognitionSettings = rekognitionOptions.Value;

    public async Task<Guid> UploadDocumentsAsync(
        Guid userId,
        KycUploadRequest request,
        CancellationToken ct = default)
    {
        logger.LogInformation("KYC upload started for user: {UserId}", userId);

        var user = await userRepository.GetByIdAsync(userId);
        if (user == null)
            throw new UnauthorizedException("User not found.");

        if (user.IsIdentityVerified)
            throw new ConflictException("Identity already verified.");

        var existing = await kycRepository.GetByUserIdAsync(userId);
        if (existing != null)
        {
            if (existing.Status == KycStatus.UnderReview)
                throw new ConflictException("Your KYC is currently under admin review. Please wait 24-48 hours.");

            if (existing.Status == KycStatus.Verified)
                throw new ConflictException("Identity already verified.");

            if (existing.AttemptCount >= MaxAttempts)
                throw new ConflictException($"Maximum {MaxAttempts} verification attempts reached. Please contact support.");
        }

        if (RequiresBackImage(request.DocumentType) && request.BackImageStream == null)
            throw new ArgumentException($"Back image is required for {request.DocumentType}.");

        var frontUrl = await imageStorage.UploadAsync(
            request.FrontImageStream,
            $"{Guid.NewGuid()}_front_{request.FrontImageFileName}",
            KycFolderName, ct);

        var selfieUrl = await imageStorage.UploadAsync(
            request.SelfieImageStream,
            $"{Guid.NewGuid()}_selfie_{request.SelfieImageFileName}",
            KycFolderName, ct);

        string? backUrl = null;
        if (request.BackImageStream != null && request.BackImageFileName != null)
        {
            backUrl = await imageStorage.UploadAsync(
                request.BackImageStream,
                $"{Guid.NewGuid()}_back_{request.BackImageFileName}",
                KycFolderName, ct);
        }

        OcrResult? ocrResult = null;
        if (SupportsOcr(request.DocumentType))
        {
            logger.LogInformation("Running OCR on {DocumentType} front image", request.DocumentType);
            ocrResult = await ocrService.ExtractTextAsync(frontUrl, request.DocumentType, ct);

            if (ocrResult.Success)
                logger.LogInformation("OCR success | Doc#: {DocNum} | Name: {Name}",
                    ocrResult.ExtractedDocumentNumber, ocrResult.ExtractedFullName);
            else
                logger.LogWarning("OCR failed: {Error}", ocrResult.ErrorMessage);
        }

        logger.LogInformation("Running face match between selfie and document");
        var faceMatchResult = await faceMatchService.CompareFacesAsync(
            sourceImageUrl: selfieUrl,
            targetImageUrl: frontUrl,
            ct: ct);

        if (faceMatchResult.Success)
            logger.LogInformation("Face match | Score: {Score:P0} | IsMatch: {Match}",
                faceMatchResult.SimilarityScore, faceMatchResult.IsMatch);
        else
            logger.LogWarning("Face match service error: {Error}", faceMatchResult.ErrorMessage);

        var finalStatus = DetermineKycStatus(ocrResult, faceMatchResult, request.DocumentType);
        string? rejectionReason = finalStatus == KycStatus.Failed
            ? BuildRejectionReason(ocrResult, faceMatchResult)
            : null;

        int newAttemptCount = (existing?.AttemptCount ?? 0) + 1;
        Guid verificationId;

        if (existing != null)
        {
            // Mutate the tracked entity — EF Core change tracking persists this on SaveChangesAsync
            existing.DocumentType = request.DocumentType;
            existing.Status = finalStatus;
            existing.FrontImageUrl = frontUrl;
            existing.BackImageUrl = backUrl;
            existing.SelfieImageUrl = selfieUrl;
            existing.ExtractedFullName = ocrResult?.ExtractedFullName;
            existing.ExtractedDocumentNumber = ocrResult?.ExtractedDocumentNumber;
            existing.ExtractedDateOfBirth = ocrResult?.ExtractedDateOfBirth;
            existing.FaceMatchScore = faceMatchResult.SimilarityScore;
            existing.RejectionReason = rejectionReason;
            existing.AttemptCount = newAttemptCount;
            existing.CreatedAt = DateTime.UtcNow;
            existing.VerifiedAt = finalStatus == KycStatus.Verified ? DateTime.UtcNow : null;
            verificationId = existing.Id;
        }
        else
        {
            var verification = new IdentityVerification
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                DocumentType = request.DocumentType,
                Status = finalStatus,
                FrontImageUrl = frontUrl,
                BackImageUrl = backUrl,
                SelfieImageUrl = selfieUrl,
                ExtractedFullName = ocrResult?.ExtractedFullName,
                ExtractedDocumentNumber = ocrResult?.ExtractedDocumentNumber,
                ExtractedDateOfBirth = ocrResult?.ExtractedDateOfBirth,
                FaceMatchScore = faceMatchResult.SimilarityScore,
                RejectionReason = rejectionReason,
                AttemptCount = 1,
                CreatedAt = DateTime.UtcNow,
                VerifiedAt = finalStatus == KycStatus.Verified ? DateTime.UtcNow : null
            };
            await kycRepository.AddAsync(verification);
            verificationId = verification.Id;
        }

        if (finalStatus == KycStatus.Verified)
        {
            user.IsIdentityVerified = true;
            user.SecurityStamp = Guid.NewGuid();
            logger.LogInformation("User auto-verified: {UserId}", userId);
        }

        await kycRepository.SaveChangesAsync();

        logger.LogInformation("KYC processed | User: {UserId} | Status: {Status} | Attempt: {Attempt}/{Max}",
            userId, finalStatus, newAttemptCount, MaxAttempts);

        return verificationId;
    }

    public async Task<KycStatusResponseDto> GetStatusAsync(Guid userId)
    {
        var verification = await kycRepository.GetByUserIdAsync(userId);

        if (verification == null)
            return new KycStatusResponseDto { HasSubmitted = false, AttemptsRemaining = MaxAttempts };

        int attemptsRemaining = verification.Status == KycStatus.Failed
            ? Math.Max(0, MaxAttempts - verification.AttemptCount)
            : 0;

        return new KycStatusResponseDto
        {
            HasSubmitted = true,
            Status = verification.Status,
            DocumentType = verification.DocumentType,
            ExtractedFullName = verification.ExtractedFullName,
            ExtractedDocumentNumber = MaskDocumentNumber(verification.ExtractedDocumentNumber),
            FaceMatchScore = verification.FaceMatchScore,
            RejectionReason = verification.RejectionReason,
            StatusMessage = BuildStatusMessage(verification),
            AttemptsRemaining = attemptsRemaining,
            SubmittedAt = verification.CreatedAt,
            VerifiedAt = verification.VerifiedAt
        };
    }

    private static bool RequiresBackImage(DocumentType documentType) =>
        documentType is DocumentType.Cnic or DocumentType.NationalId;

    private static bool SupportsOcr(DocumentType documentType) =>
        documentType is DocumentType.Cnic or DocumentType.Passport;

    // Score thresholds (settings stored as %, score is 0.0–1.0):
    //   >= AutoVerifyThreshold  → Verified   (auto-approved)
    //   >= ManualReviewThreshold → UnderReview (admin reviews within 24-48h)
    //   <  ManualReviewThreshold → Failed     (user may retry up to MaxAttempts)
    private KycStatus DetermineKycStatus(
        OcrResult? ocrResult,
        FaceMatchResult faceMatchResult,
        DocumentType documentType)
    {
        // AWS errors or transient failures go to admin review rather than auto-reject
        if (!faceMatchResult.Success)
            return KycStatus.UnderReview;

        if (SupportsOcr(documentType) && (ocrResult == null || !ocrResult.Success))
            return KycStatus.UnderReview;

        var score = faceMatchResult.SimilarityScore;
        var autoVerifyThreshold = _rekognitionSettings.AutoVerifyThreshold / 100.0;
        var manualReviewThreshold = _rekognitionSettings.ManualReviewThreshold / 100.0;

        if (score >= autoVerifyThreshold)
            return KycStatus.Verified;

        if (score >= manualReviewThreshold)
            return KycStatus.UnderReview;

        return KycStatus.Failed;
    }

    private static string BuildRejectionReason(OcrResult? ocrResult, FaceMatchResult faceMatchResult)
    {
        var reasons = new List<string>();

        if (ocrResult != null && !ocrResult.Success)
            reasons.Add($"OCR failed: {ocrResult.ErrorMessage}");

        if (!faceMatchResult.Success)
            reasons.Add($"Face match error: {faceMatchResult.ErrorMessage}");
        else
            reasons.Add($"Face similarity too low ({faceMatchResult.SimilarityScore:P0})");

        return string.Join(" | ", reasons);
    }

    private static string BuildStatusMessage(IdentityVerification verification) =>
        verification.Status switch
        {
            KycStatus.Verified =>
                "Your identity has been successfully verified.",
            KycStatus.UnderReview =>
                "Your KYC is under admin review. Please allow 24-48 hours for verification.",
            KycStatus.Failed when verification.AttemptCount >= MaxAttempts =>
                "Verification failed. You have reached the maximum number of attempts. Please contact support.",
            KycStatus.Failed =>
                $"Verification failed. You have {MaxAttempts - verification.AttemptCount} attempt(s) remaining.",
            _ => string.Empty
        };

    private static string? MaskDocumentNumber(string? docNumber)
    {
        if (string.IsNullOrEmpty(docNumber) || docNumber.Length <= 4)
            return docNumber;

        return new string('*', docNumber.Length - 4) + docNumber[^4..];
    }
}
