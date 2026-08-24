using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class SuggestionDismissalConfiguration : IEntityTypeConfiguration<SuggestionDismissal>
{
    public void Configure(EntityTypeBuilder<SuggestionDismissal> builder)
    {
        builder.ToTable("SuggestionDismissals");

        builder.HasKey(d => d.Id);

        builder.Property(d => d.CreatedAt).IsRequired();

        builder.HasOne(d => d.User)
            .WithMany()
            .HasForeignKey(d => d.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(d => d.DismissedUser)
            .WithMany()
            .HasForeignKey(d => d.DismissedUserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.Property(d => d.Kind)
            .IsRequired()
            .HasDefaultValue(SuggestionKind.Connect);

        builder.HasIndex(d => d.UserId)
            .HasDatabaseName("IX_SuggestionDismissals_UserId");

        // Unique per (user, dismissed-user, kind): connect-dismiss and follow-dismiss are
        // independent — the same pair can be dismissed from both feeds simultaneously.
        builder.HasIndex(d => new { d.UserId, d.DismissedUserId, d.Kind })
            .IsUnique()
            .HasDatabaseName("IX_SuggestionDismissals_UserId_DismissedUserId_Kind");
    }
}
