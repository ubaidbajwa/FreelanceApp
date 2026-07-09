using FreelanceApp.Domain.Entities;
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

        // PasswordHash — BCrypt hashes are around 60 chars, give buffer
        builder.Property(u => u.PasswordHash)
            .IsRequired()
            .HasMaxLength(255);

        // FullName
        builder.Property(u => u.FullName)
            .IsRequired()
            .HasMaxLength(100);

        // Role: "Freelancer", "Client", "Admin"
        builder.Property(u => u.Role)
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