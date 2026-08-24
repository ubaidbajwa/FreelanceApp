using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace FreelanceApp.Infrastructure.Persistence;

// Design-time only. `dotnet ef` uses this to build the model for `migrations add` WITHOUT running
// the Api's Program.cs (which fails fast when the JWT secret / connection string live only in
// user-secrets). No database connection is made when adding a migration — the connection string
// just has to be a valid Npgsql shape so the provider initializes. This type is never used at runtime.
public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql("Host=localhost;Database=freelanceapp_design;Username=postgres;Password=postgres")
            .Options;
        return new AppDbContext(options);
    }
}
