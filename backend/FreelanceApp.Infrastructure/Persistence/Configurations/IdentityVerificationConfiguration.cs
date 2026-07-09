using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class IdentityVerificationConfiguration : IEntityTypeConfiguration<IdentityVerification>
{
    public void Configure(EntityTypeBuilder<IdentityVerification> builder)
    {
        // Table name
        builder.ToTable("IdentityVerifications");

        // Primary Key
        builder.HasKey(v => v.Id);

        // Enums stored as int
        builder.Property(v => v.DocumentType)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(v => v.Status)
            .IsRequired()
            .HasConversion<int>();

        // Image URLs
        builder.Property(v => v.FrontImageUrl)
            .IsRequired()
            .HasMaxLength(500);

        builder.Property(v => v.BackImageUrl)
            .HasMaxLength(500);   // nullable — no IsRequired

        builder.Property(v => v.SelfieImageUrl)
            .IsRequired()
            .HasMaxLength(500);

        // OCR extracted fields (nullable)
        builder.Property(v => v.ExtractedFullName).HasMaxLength(200);
        builder.Property(v => v.ExtractedDocumentNumber).HasMaxLength(50);

        // Default values
        builder.Property(v => v.AttemptCount).HasDefaultValue(0);
        builder.Property(v => v.CreatedAt).IsRequired();

        // Rejection reason
        builder.Property(v => v.RejectionReason).HasMaxLength(500);

        // Relationship: One User → One IdentityVerification (1-to-1)
        builder.HasOne(v => v.User)
            .WithMany()
            .HasForeignKey(v => v.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        // Index for fast lookup by user
        builder.HasIndex(v => v.UserId)
            .HasDatabaseName("IX_IdentityVerifications_UserId");
    }
}