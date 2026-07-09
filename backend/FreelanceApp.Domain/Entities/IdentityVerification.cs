using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Domain.Entities;

public class IdentityVerification
{
    // ===== Group 1: Basic Info =====
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public DocumentType DocumentType { get; set; }
    public KycStatus Status { get; set; }

    // ===== Group 2: Image URLs (stored in Cloudinary/S3) =====
    public string FrontImageUrl { get; set; } = string.Empty;
    public string? BackImageUrl { get; set; }       // CNIC ke liye, Passport mein null
    public string SelfieImageUrl { get; set; } = string.Empty;

    // ===== Group 3: OCR Extracted Data =====
    public string? ExtractedFullName { get; set; }
    public string? ExtractedDocumentNumber { get; set; }
    public DateOnly? ExtractedDateOfBirth { get; set; }

    // ===== Group 4: Verification Results =====
    public double? FaceMatchScore { get; set; }      // 0.0 - 1.0 (e.g., 0.85 = 85%)
    public string? RejectionReason { get; set; }     // Agar fail hua, kyun
    public int AttemptCount { get; set; }            // Kitni baar try kiya

    // ===== Timestamps =====
    public DateTime CreatedAt { get; set; }
    public DateTime? VerifiedAt { get; set; }        // Verify hone ka time

    // ===== Navigation Property =====
    public User? User { get; set; }
}