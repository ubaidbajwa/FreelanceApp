using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class MessagePlayConfiguration : IEntityTypeConfiguration<MessagePlay>
{
    public void Configure(EntityTypeBuilder<MessagePlay> builder)
    {
        builder.ToTable("MessagePlays");

        // Composite PK — one "played" record per (message, user). Idempotent by design:
        // marking played again is a no-op (the row already exists).
        builder.HasKey(p => new { p.MessageId, p.UserId });

        builder.Property(p => p.PlayedAt).IsRequired();

        // A played record dies with its message — Cascade.
        builder.HasOne(p => p.Message)
            .WithMany(m => m.Plays)
            .HasForeignKey(p => p.MessageId)
            .OnDelete(DeleteBehavior.Cascade);

        // FK to User — Restrict, consistent with the other message FKs.
        builder.HasOne<User>()
            .WithMany()
            .HasForeignKey(p => p.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        // Drives the per-message played-flag projection (playedByMe / playedByOther EXISTS subqueries).
        builder.HasIndex(p => p.MessageId)
            .HasDatabaseName("IX_MessagePlays_MessageId");
    }
}
