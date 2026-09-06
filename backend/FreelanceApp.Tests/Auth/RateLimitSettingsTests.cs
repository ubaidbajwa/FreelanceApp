using FreelanceApp.Application.Common.Settings;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace FreelanceApp.Tests.Auth;

// Integration-testing the live middleware would need WebApplicationFactory (new to this project) and
// wall-clock windows — disproportionate for a config-bound limiter. Instead we assert what actually
// matters and is deterministic: the "RateLimiting" section binds to RateLimitSettings, the values
// resolve as configured, and the Window helper derives correctly. The policy REGISTRATION itself is
// exercised by the app at startup (a bad policy name throws), so it is not re-mocked here.
public class RateLimitSettingsTests
{
    private static RateLimitSettings Bind(Dictionary<string, string?> values) =>
        new ConfigurationBuilder().AddInMemoryCollection(values).Build()
            .GetSection(RateLimitSettings.SectionName).Get<RateLimitSettings>() ?? new RateLimitSettings();

    [Fact]
    public void Binds_AllPolicies_FromConfiguration()
    {
        var settings = Bind(new Dictionary<string, string?>
        {
            ["RateLimiting:Login:PermitLimit"] = "5",
            ["RateLimiting:Login:WindowMinutes"] = "15",
            ["RateLimiting:Register:PermitLimit"] = "3",
            ["RateLimiting:Register:WindowMinutes"] = "60",
            ["RateLimiting:ForgotPassword:PermitLimit"] = "3",
            ["RateLimiting:ForgotPassword:WindowMinutes"] = "60",
            ["RateLimiting:Otp:PermitLimit"] = "5",
            ["RateLimiting:Otp:WindowMinutes"] = "15",
            ["RateLimiting:Media:PermitLimit"] = "20",
            ["RateLimiting:Media:WindowMinutes"] = "60",
            ["RateLimiting:Authenticated:PermitLimit"] = "300",
            ["RateLimiting:Authenticated:WindowMinutes"] = "1",
            ["RateLimiting:Anonymous:PermitLimit"] = "60",
            ["RateLimiting:Anonymous:WindowMinutes"] = "1",
        });

        Assert.Equal(5, settings.Login.PermitLimit);
        Assert.Equal(TimeSpan.FromMinutes(15), settings.Login.Window);
        Assert.Equal(3, settings.Register.PermitLimit);
        Assert.Equal(TimeSpan.FromHours(1), settings.Register.Window);
        Assert.Equal(3, settings.ForgotPassword.PermitLimit);
        Assert.Equal(TimeSpan.FromHours(1), settings.ForgotPassword.Window);
        Assert.Equal(5, settings.Otp.PermitLimit);
        Assert.Equal(20, settings.Media.PermitLimit);
        Assert.Equal(TimeSpan.FromHours(1), settings.Media.Window);
        Assert.Equal(300, settings.Authenticated.PermitLimit);
        Assert.Equal(60, settings.Anonymous.PermitLimit);
    }

    [Fact]
    public void Overrides_TuneWithoutRedeploy()
    {
        // The whole point of settings-binding: a production tune changes the value with no code change.
        var settings = Bind(new Dictionary<string, string?>
        {
            ["RateLimiting:Login:PermitLimit"] = "2",
            ["RateLimiting:Login:WindowMinutes"] = "30",
        });

        Assert.Equal(2, settings.Login.PermitLimit);
        Assert.Equal(TimeSpan.FromMinutes(30), settings.Login.Window);
    }

    [Fact]
    public void Defaults_AreSafe_WhenSectionAbsent()
    {
        // Empty config → the limiter is still safe out of the box (defaults on RateLimitSettings).
        var settings = Bind(new Dictionary<string, string?>());

        Assert.Equal(5, settings.Login.PermitLimit);
        Assert.Equal(15, settings.Login.WindowMinutes);
        Assert.Equal(3, settings.ForgotPassword.PermitLimit);
        Assert.Equal(20, settings.Media.PermitLimit);
        Assert.Equal(300, settings.Authenticated.PermitLimit);
    }
}
