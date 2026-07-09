using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class EmailOtpConfiguration : IEntityTypeConfiguration<EmailOtp>
{
    public void Configure(EntityTypeBuilder<EmailOtp> builder)
    {
        // Table name
        builder.ToTable("EmailOtps");

        // Primary Key
        builder.HasKey(o => o.Id);

        // Column constraints
        builder.Property(o => o.Code)
            .IsRequired()
            .HasMaxLength(6);

        builder.Property(o => o.Purpose)
            .IsRequired()
            .HasConversion<int>();  // Enum stored as int in DB

        builder.Property(o => o.ExpiresAt).IsRequired();
        builder.Property(o => o.CreatedAt).IsRequired();

        // Default values
        builder.Property(o => o.IsUsed).HasDefaultValue(false);
        builder.Property(o => o.AttemptCount).HasDefaultValue(0);

        // Relationship: EmailOtp belongs to a User
        builder.HasOne(o => o.User)
            .WithMany()
            .HasForeignKey(o => o.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        // Indexes for fast queries
        builder.HasIndex(o => new { o.UserId, o.Purpose })
            .HasDatabaseName("IX_EmailOtps_UserId_Purpose");

        builder.HasIndex(o => o.ExpiresAt)
            .HasDatabaseName("IX_EmailOtps_ExpiresAt");
    }
}