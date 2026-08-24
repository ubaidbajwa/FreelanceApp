using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class ProfileConfiguration : IEntityTypeConfiguration<Profile>
{
    public void Configure(EntityTypeBuilder<Profile> builder)
    {
        // Table name
        builder.ToTable("Profiles");

        // Primary Key
        builder.HasKey(p => p.Id);

        builder.Property(p => p.DisplayName)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(p => p.Headline).HasMaxLength(150);
        builder.Property(p => p.Bio).HasMaxLength(2000);
        builder.Property(p => p.ProfilePhotoUrl).HasMaxLength(500);

        builder.Property(p => p.HourlyRate)
            .HasPrecision(10, 2);

        // Nullable enums stored as int
        builder.Property(p => p.Availability).HasConversion<int?>();
        builder.Property(p => p.WorkPreference).HasConversion<int?>();
        builder.Property(p => p.AvailabilityStatus).HasConversion<int?>();
        builder.Property(p => p.ClientType).HasConversion<int?>();

        builder.Property(p => p.BusinessName).HasMaxLength(100);

        builder.Property(p => p.Country).HasMaxLength(100);
        builder.Property(p => p.City).HasMaxLength(100);

        // Username — hamesha lowercase store hota hai (service normalize karta hai),
        // isliye plain unique index hi case-insensitive uniqueness deta hai
        builder.Property(p => p.Username).HasMaxLength(30);
        builder.HasIndex(p => p.Username)
            .IsUnique()
            .HasDatabaseName("IX_Profiles_Username");

        builder.Property(p => p.HiringType).HasConversion<int?>();
        builder.Property(p => p.InvitePolicy).HasConversion<int?>();

        // Postgres text[] — Npgsql List<string> ko natively map karta hai
        builder.Property(p => p.Skills)
            .HasColumnType("text[]");
        builder.Property(p => p.DesiredJobTitles)
            .HasColumnType("text[]");
        builder.Property(p => p.DesiredJobLocations)
            .HasColumnType("text[]");
        builder.Property(p => p.HiringInterests)
            .HasColumnType("text[]")
            .HasDefaultValueSql("'{}'");

        builder.Property(p => p.CreatedAt).IsRequired();
        builder.Property(p => p.UpdatedAt).IsRequired();

        // One User → One Profile (1-to-1) — FK unique index ke sath
        builder.HasOne(p => p.User)
            .WithOne()
            .HasForeignKey<Profile>(p => p.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasIndex(p => p.UserId)
            .IsUnique()
            .HasDatabaseName("IX_Profiles_UserId");
    }
}
