using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> builder)
    {
        // Table name
        builder.ToTable("Users");

        // Primary Key
        builder.HasKey(u => u.Id);

        // Email — most important field
        builder.Property(u => u.Email)
            .IsRequired()
            .HasMaxLength(255);

        // Email must be UNIQUE — no duplicate accounts
        builder.HasIndex(u => u.Email)
            .IsUnique()
            .HasDatabaseName("IX_Users_Email");

        // PasswordHash — BCrypt hashes are around 60 chars, give buffer.
        // NOT required: social-login users (Google/MS/Apple) have no password.
        builder.Property(u => u.PasswordHash)
            .HasMaxLength(255);

        // FullName
        builder.Property(u => u.FullName)
            .IsRequired()
            .HasMaxLength(100);

        // How the account was created. Stored as int; default Local (0).
        builder.Property(u => u.Provider)
            .IsRequired()
            .HasDefaultValue(AuthProvider.Local);

        // Provider's stable user id (e.g. Google "sub"). Null for Local accounts.
        builder.Property(u => u.ExternalId)
            .HasMaxLength(255);

        // PrimaryRole: default experience only (not a permission boundary). Stored as int.
        builder.Property(u => u.PrimaryRole)
            .IsRequired()
            .HasMaxLength(20);

        // Verification flags — default false for new users
        builder.Property(u => u.IsIdentityVerified).HasDefaultValue(false);
        builder.Property(u => u.IsEmailVerified).HasDefaultValue(false);

        // SecurityStamp — for instant session revocation
        builder.Property(u => u.SecurityStamp)
            .IsRequired();

        // Timestamps
        builder.Property(u => u.CreatedAt).IsRequired();
    }
}