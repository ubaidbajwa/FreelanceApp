using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;

namespace FreelanceApp.Infrastructure.Persistence;

// Design-time ONLY — lets `dotnet ef` (migrations add / database update) build & apply
// migrations without spinning up the API host (which may be running / locking DLLs).
// Reads the SAME connection the API uses (user-secrets → env), so `database update`
// targets the real Neon database, not localhost.
public class AppDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    // API project's UserSecretsId — user-secrets live in a per-user store, so this
    // resolves regardless of the current working directory.
    private const string ApiUserSecretsId = "e5cc50a4-a1c5-46a8-b7ab-cda45c2195a9";

    public AppDbContext CreateDbContext(string[] args)
    {
        var config = new ConfigurationBuilder()
            .AddUserSecrets(ApiUserSecretsId)
            .AddEnvironmentVariables()
            .Build();

        var connectionString = config.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException(
                "DefaultConnection not found for design-time DbContext " +
                "(checked user-secrets + environment variables).");

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(connectionString)
            .Options;

        return new AppDbContext(options);
    }
}
