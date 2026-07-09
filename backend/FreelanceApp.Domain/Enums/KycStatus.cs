namespace FreelanceApp.Domain.Enums;

public enum KycStatus
{
    Pending = 1,        // User has not submitted KYC yet
    UnderReview = 2,    // KYC submitted, under AI or admin review
    Verified = 3,       // All checks passed — user is verified
    Failed = 4          // Verification failed — retry or admin review required
}