using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class MessageDeletionConfiguration : IEntityTypeConfiguration<MessageDeletion>
{
    public void Configure(EntityTypeBuilder<MessageDeletion> builder)
    {
        builder.ToTable("MessageDeletions");

        // Composite PK — one "delete for me" tombstone per (message, user). Idempotent by design:
        // deleting again is a no-op (the row already exists).
        builder.HasKey(d => new { d.MessageId, d.UserId });

        builder.Property(d => d.DeletedAt).IsRequired();

        // A per-user tombstone dies with its message — Cascade.
        builder.HasOne(d => d.Message)
            .WithMany(m => m.Deletions)
            .HasForeignKey(d => d.MessageId)
            .OnDelete(DeleteBehavior.Cascade);

        // FK to User — Restrict, consistent with the other message FKs.
        builder.HasOne<User>()
            .WithMany()
            .HasForeignKey(d => d.UserId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}
