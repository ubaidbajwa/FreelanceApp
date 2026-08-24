using FreelanceApp.Application.Common.Capabilities;
using Xunit;

namespace FreelanceApp.Tests.Capabilities;

public class UserCapabilitiesTests
{
    // ===== CanHire — always true for any authenticated user =====

    [Theory]
    [InlineData(false, 0)]
    [InlineData(true, 0)]
    [InlineData(true, 100)]
    public void CanHire_IsAlwaysTrue(bool profileExists, int completionPercent)
    {
        var caps = UserCapabilities.Evaluate(profileExists, completionPercent);
        Assert.True(caps.CanHire);
    }

    // ===== CanFreelance — needs a profile AND >= 50% completion =====

    [Fact]
    public void CanFreelance_False_WhenProfileMissing()
    {
        // No profile → cannot freelance, regardless of percent argument.
        var caps = UserCapabilities.Evaluate(profileExists: false, completionPercent: 100);
        Assert.False(caps.CanFreelance);
    }

    [Fact]
    public void CanFreelance_False_WhenCompletionBelowThreshold()
    {
        // 49% → just under the bar → false.
        var caps = UserCapabilities.Evaluate(profileExists: true, completionPercent: 49);
        Assert.False(caps.CanFreelance);
    }

    [Fact]
    public void CanFreelance_True_WhenCompletionAtThreshold()
    {
        // Exactly 50% → true (threshold is inclusive).
        var caps = UserCapabilities.Evaluate(profileExists: true, completionPercent: 50);
        Assert.True(caps.CanFreelance);
    }

    [Fact]
    public void CanFreelance_True_WhenCompletionAboveThreshold()
    {
        var caps = UserCapabilities.Evaluate(profileExists: true, completionPercent: 80);
        Assert.True(caps.CanFreelance);
    }
}
