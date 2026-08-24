using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class MessageReactionConfiguration : IEntityTypeConfiguration<MessageReaction>
{
    public void Configure(EntityTypeBuilder<MessageReaction> builder)
    {
        builder.ToTable("MessageReactions");

        // Composite PK — one reaction per (message, user). Reacting again UPDATEs this row's Emoji.
        builder.HasKey(r => new { r.MessageId, r.UserId });

        builder.Property(r => r.Emoji)
            .IsRequired()
            .HasMaxLength(16);

        builder.Property(r => r.CreatedAt).IsRequired();

        // Reactions die WITH their message — Cascade.
        builder.HasOne(r => r.Message)
            .WithMany(m => m.Reactions)
            .HasForeignKey(r => r.MessageId)
            .OnDelete(DeleteBehavior.Cascade);

        // FK to User — Restrict (deleting a user must not silently vacuum their reaction history,
        // consistent with Message.Sender). No navigation from User needed.
        builder.HasOne<User>()
            .WithMany()
            .HasForeignKey(r => r.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        // Drives the per-message reaction aggregate.
        builder.HasIndex(r => r.MessageId)
            .HasDatabaseName("IX_MessageReactions_MessageId");
    }
}
