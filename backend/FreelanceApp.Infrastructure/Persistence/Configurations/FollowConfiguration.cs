using FreelanceApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace FreelanceApp.Infrastructure.Persistence.Configurations;

public class FollowConfiguration : IEntityTypeConfiguration<Follow>
{
    public void Configure(EntityTypeBuilder<Follow> builder)
    {
        builder.ToTable("Follows");

        builder.HasKey(f => f.Id);

        builder.Property(f => f.CreatedAt).IsRequired();

        builder.HasOne(f => f.Follower)
            .WithMany()
            .HasForeignKey(f => f.FollowerId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(f => f.Followee)
            .WithMany()
            .HasForeignKey(f => f.FolloweeId)
            .OnDelete(DeleteBehavior.Cascade);

        // Prevents duplicate follows; also serves as the FollowerId prefix index
        builder.HasIndex(f => new { f.FollowerId, f.FolloweeId })
            .IsUnique()
            .HasDatabaseName("IX_Follows_FollowerId_FolloweeId");

        // Supports GetFollowersAsync (WHERE FolloweeId = me) + followers count
        builder.HasIndex(f => f.FolloweeId)
            .HasDatabaseName("IX_Follows_FolloweeId");

        // Supports GetFollowingAsync (WHERE FollowerId = me) + following count
        builder.HasIndex(f => f.FollowerId)
            .HasDatabaseName("IX_Follows_FollowerId");
    }
}
