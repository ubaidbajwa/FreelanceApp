using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class ConversationConfiguration : IEntityTypeConfiguration<Conversation>
{
    public void Configure(EntityTypeBuilder<Conversation> builder)
    {
        builder.ToTable("Conversations");

        builder.HasKey(c => c.Id);

        // Enum stored as int
        builder.Property(c => c.Status)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(c => c.InitiatorId).IsRequired();
        builder.Property(c => c.CreatedAt).IsRequired();
        // LastMessageAt nullable — null jab tak pehla message na aaye
        // RespondedAt nullable — null = abhi Pending

        // Participants aur Messages Conversation ke saath cascade-delete hote hain
        // (conversation config on the "one" side; FK + cascade child configs mein).

        // List ordering (recent-first) isi index se chalti hai
        builder.HasIndex(c => c.LastMessageAt)
            .HasDatabaseName("IX_Conversations_LastMessageAt");

        // Pending request lookup by initiator — "1 message tak request" rule enforce karne mein
        builder.HasIndex(c => new { c.InitiatorId, c.Status })
            .HasDatabaseName("IX_Conversations_InitiatorId_Status");
    }
}
