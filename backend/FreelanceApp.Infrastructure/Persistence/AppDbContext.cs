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

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.ApplyConfiguration(new UserConfiguration());
        modelBuilder.ApplyConfiguration(new EmailOtpConfiguration());
        modelBuilder.ApplyConfiguration(new IdentityVerificationConfiguration());
    }
}