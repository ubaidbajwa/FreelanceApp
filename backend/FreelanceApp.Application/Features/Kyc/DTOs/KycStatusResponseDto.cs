using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Kyc.DTOs;

public class KycStatusResponseDto
{
    public bool HasSubmitted { get; set; }
    public KycStatus? Status { get; set; }
    public DocumentType? DocumentType { get; set; }
    public string? ExtractedFullName { get; set; }
    public string? ExtractedDocumentNumber { get; set; }
    public double? FaceMatchScore { get; set; }
    public string? RejectionReason { get; set; }
    public string? StatusMessage { get; set; }       // User-friendly message (e.g. wait 24-48 hours)
    public int AttemptsRemaining { get; set; }       // How many retries the user has left
    public DateTime? SubmittedAt { get; set; }
    public DateTime? VerifiedAt { get; set; }
}