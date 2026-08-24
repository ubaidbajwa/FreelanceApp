using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class ExperienceConfiguration : IEntityTypeConfiguration<Experience>
{
    public void Configure(EntityTypeBuilder<Experience> builder)
    {
        // Table name
        builder.ToTable("Experiences");

        // Primary Key
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Title)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(e => e.Company)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(e => e.Description).HasMaxLength(1000);

        builder.Property(e => e.StartDate).IsRequired();
        // EndDate nullable — null = current position

        // One Profile → Many Experiences, profile delete pe experiences bhi delete
        builder.HasOne(e => e.Profile)
            .WithMany(p => p.Experiences)
            .HasForeignKey(e => e.ProfileId)
            .OnDelete(DeleteBehavior.Cascade);

        // Index for fast lookup by profile
        builder.HasIndex(e => e.ProfileId)
            .HasDatabaseName("IX_Experiences_ProfileId");
    }
}
