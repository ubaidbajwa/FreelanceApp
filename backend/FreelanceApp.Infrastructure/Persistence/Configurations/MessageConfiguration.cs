using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class MessageConfiguration : IEntityTypeConfiguration<Message>
{
    public void Configure(EntityTypeBuilder<Message> builder)
    {
        builder.ToTable("Messages");

        builder.HasKey(m => m.Id);

        builder.Property(m => m.Body)
            .IsRequired()
            .HasMaxLength(4000);

        // Enum stored as int
        builder.Property(m => m.Type)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(m => m.CreatedAt).IsRequired();
        // DeletedAt nullable — "delete for everyone" tombstone, null = live message
        // EditedAt / PinnedAt / PinnedByUserId / ForwardedFromMessageId all nullable (additive, M1.2)

        // Conversation delete pe uske messages bhi delete
        builder.HasOne(m => m.Conversation)
            .WithMany(c => c.Messages)
            .HasForeignKey(m => m.ConversationId)
            .OnDelete(DeleteBehavior.Cascade);

        // User delete pe uski message history NA delete ho — Restrict
        builder.HasOne(m => m.Sender)
            .WithMany()
            .HasForeignKey(m => m.SenderId)
            .OnDelete(DeleteBehavior.Restrict);

        // Reply: self-referencing FK. RESTRICT (not Cascade) is the whole point — cascading would
        // delete every reply when the quoted message is deleted. A reply must survive its quoted
        // message and render a "message deleted" placeholder instead.
        builder.HasOne(m => m.ReplyToMessage)
            .WithMany()
            .HasForeignKey(m => m.ReplyToMessageId)
            .OnDelete(DeleteBehavior.Restrict);

        // Forward: ForwardedFromMessageId is deliberately a PLAIN column, NOT a FK. The source
        // message usually lives in a different conversation and must be independently deletable;
        // a FK (even Restrict) would couple the two conversations' lifecycles. It is used only to
        // render a "Forwarded" label.

        // SystemEventType stored as nullable int (same convention as Type).
        builder.Property(m => m.SystemEventType)
            .HasColumnType("integer");

        // ===== Media columns (M-M4, additive, all nullable) =====
        // Body keeps IsRequired() above — for media it holds the caption, and an empty string still
        // satisfies NOT NULL, so no existing read path changes and the column need not become nullable.
        builder.Property(m => m.MediaUrl).HasMaxLength(500);
        builder.Property(m => m.MediaThumbnailUrl).HasMaxLength(500);
        builder.Property(m => m.MediaMimeType).HasMaxLength(100);
        builder.Property(m => m.MediaPublicId).HasMaxLength(255);
        // Document original filename (M-M8): sanitised before storage; 255 is the conventional filename cap.
        builder.Property(m => m.MediaFileName).HasMaxLength(255);
        // Voice waveform (M-M6): comma-separated amplitude samples. 512 bounds it (64×3 + 63 ≤ 255).
        builder.Property(m => m.MediaWaveform).HasMaxLength(512);
        // MediaWidth / MediaHeight / MediaDurationMs (int?) and MediaSizeBytes (long?) map to
        // nullable integer / bigint by convention — no explicit configuration needed.

        // Cursor pagination isi composite index se chalti hai (thread ke messages, time order)
        builder.HasIndex(m => new { m.ConversationId, m.CreatedAt })
            .HasDatabaseName("IX_Messages_ConversationId_CreatedAt");

        // Original pin lookup index (retained — pre-duration rows have PinExpiresAt = null).
        builder.HasIndex(m => new { m.ConversationId, m.PinnedAt })
            .HasDatabaseName("IX_Messages_ConversationId_PinnedAt");

        // Composite index for active-pin lookups (GetPinnedAsync, CountPinnedAsync, GetOldestActivePinAsync).
        builder.HasIndex(m => new { m.ConversationId, m.PinnedAt, m.PinExpiresAt })
            .HasDatabaseName("IX_Messages_ConversationId_PinnedAt_PinExpiresAt");
    }
}
