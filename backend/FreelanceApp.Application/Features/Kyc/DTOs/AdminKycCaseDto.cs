using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Kyc.DTOs;

public class AdminKycCaseDto
{
    public Guid VerificationId { get; set; }
    public Guid UserId { get; set; }
    public string UserEmail { get; set; } = string.Empty;
    public string UserFullName { get; set; } = string.Empty;
    public DocumentType DocumentType { get; set; }
    public string FrontImageUrl { get; set; } = string.Empty;
    public string? BackImageUrl { get; set; }
    public string SelfieImageUrl { get; set; } = string.Empty;
    public string? ExtractedFullName { get; set; }
    public string? ExtractedDocumentNumber { get; set; }
    public DateOnly? ExtractedDateOfBirth { get; set; }
    public double? FaceMatchScore { get; set; }
    public int AttemptCount { get; set; }
    public DateTime SubmittedAt { get; set; }
}
