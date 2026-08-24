using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class ConversationParticipantConfiguration : IEntityTypeConfiguration<ConversationParticipant>
{
    public void Configure(EntityTypeBuilder<ConversationParticipant> builder)
    {
        builder.ToTable("ConversationParticipants");

        // Composite PK — ek user ek conversation mein sirf ek baar
        builder.HasKey(p => new { p.ConversationId, p.UserId });

        builder.Property(p => p.JoinedAt).IsRequired();
        // LastReadAt nullable — read-receipt watermark, null = kuch nahi padha

        // Conversation delete pe uske participants bhi delete
        builder.HasOne(p => p.Conversation)
            .WithMany(c => c.Participants)
            .HasForeignKey(p => p.ConversationId)
            .OnDelete(DeleteBehavior.Cascade);

        // User delete pe uski message/participant history NA delete ho — Restrict
        builder.HasOne(p => p.User)
            .WithMany()
            .HasForeignKey(p => p.UserId)
            .OnDelete(DeleteBehavior.Restrict);

        // "My conversations" query isi index se chalti hai
        builder.HasIndex(p => p.UserId)
            .HasDatabaseName("IX_ConversationParticipants_UserId");
    }
}
