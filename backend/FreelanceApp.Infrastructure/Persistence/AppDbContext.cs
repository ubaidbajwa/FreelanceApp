using FreelanceApp.Domain.Entities;
using FreelanceApp.Infrastructure.Persistence.Configurations;
using Microsoft.EntityFrameworkCore;

namespace FreelanceApp.Infrastructure.Persistence;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<User> Users { get; set; } = null!;
    public DbSet<EmailOtp> EmailOtps { get; set; } = null!;
    public DbSet<IdentityVerification> IdentityVerifications { get; set; }
    public DbSet<Profile> Profiles { get; set; } = null!;
    public DbSet<Experience> Experiences { get; set; } = null!;
    public DbSet<Connection> Connections { get; set; } = null!;
    public DbSet<SuggestionDismissal> SuggestionDismissals { get; set; } = null!;
    public DbSet<Follow> Follows { get; set; } = null!;
    public DbSet<Conversation> Conversations { get; set; } = null!;
    public DbSet<ConversationParticipant> ConversationParticipants { get; set; } = null!;
    public DbSet<Message> Messages { get; set; } = null!;
    public DbSet<MessageReaction> MessageReactions { get; set; } = null!;
    public DbSet<MessageDeletion> MessageDeletions { get; set; } = null!;

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.ApplyConfiguration(new UserConfiguration());
        modelBuilder.ApplyConfiguration(new EmailOtpConfiguration());
        modelBuilder.ApplyConfiguration(new IdentityVerificationConfiguration());
        modelBuilder.ApplyConfiguration(new ProfileConfiguration());
        modelBuilder.ApplyConfiguration(new ExperienceConfiguration());
        modelBuilder.ApplyConfiguration(new ConnectionConfiguration());
        modelBuilder.ApplyConfiguration(new SuggestionDismissalConfiguration());
        modelBuilder.ApplyConfiguration(new FollowConfiguration());
        modelBuilder.ApplyConfiguration(new ConversationConfiguration());
        modelBuilder.ApplyConfiguration(new ConversationParticipantConfiguration());
        modelBuilder.ApplyConfiguration(new MessageConfiguration());
        modelBuilder.ApplyConfiguration(new MessageReactionConfiguration());
        modelBuilder.ApplyConfiguration(new MessageDeletionConfiguration());
    }
}