using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class ConnectionConfiguration : IEntityTypeConfiguration<Connection>
{
    public void Configure(EntityTypeBuilder<Connection> builder)
    {
        // Table name
        builder.ToTable("Connections");

        // Primary Key
        builder.HasKey(c => c.Id);

        // Enum stored as int
        builder.Property(c => c.Status)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(c => c.CreatedAt).IsRequired();
        // RespondedAt nullable — null = abhi Pending

        // Relationships: dono FKs User pe — user delete pe uski connections bhi delete
        builder.HasOne(c => c.Requester)
            .WithMany()
            .HasForeignKey(c => c.RequesterId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(c => c.Receiver)
            .WithMany()
            .HasForeignKey(c => c.ReceiverId)
            .OnDelete(DeleteBehavior.Cascade);

        // Indexes for fast lookup by either side
        builder.HasIndex(c => c.RequesterId)
            .HasDatabaseName("IX_Connections_RequesterId");

        builder.HasIndex(c => c.ReceiverId)
            .HasDatabaseName("IX_Connections_ReceiverId");

        // Ek direction mein sirf ek row (A→B duplicate DB-level block).
        // Cross-direction (B→A) duplicates service layer mein enforce hote hain.
        builder.HasIndex(c => new { c.RequesterId, c.ReceiverId })
            .IsUnique()
            .HasDatabaseName("IX_Connections_RequesterId_ReceiverId");

        // Composite indexes for suggestion FOF queries — filter by both side AND status
        // without a separate Status filter pass over the full single-column index.
        builder.HasIndex(c => new { c.RequesterId, c.Status })
            .HasDatabaseName("IX_Connections_RequesterId_Status");

        builder.HasIndex(c => new { c.ReceiverId, c.Status })
            .HasDatabaseName("IX_Connections_ReceiverId_Status");
    }
}
