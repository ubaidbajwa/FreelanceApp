namespace FreelanceApp.Application.Common.Settings;

// Rate-limit policy values, bound from the "RateLimiting" configuration section so limits can be
// tuned in production without a redeploy. Each policy is a fixed window (hard ceiling per period —
// never a token bucket, which would let an attacker sustain a steady trickle). Defaults below apply
// when the section is absent, so the limiter is safe out of the box.
public class RateLimitSettings
{
    public const string SectionName = "RateLimiting";

    // Pre-auth endpoints — partitioned by client IP.
    public RateLimitPolicy Login { get; set; } = new() { PermitLimit = 5, WindowMinutes = 15 };
    public RateLimitPolicy Register { get; set; } = new() { PermitLimit = 3, WindowMinutes = 60 };
    public RateLimitPolicy ForgotPassword { get; set; } = new() { PermitLimit = 3, WindowMinutes = 60 };
    public RateLimitPolicy Otp { get; set; } = new() { PermitLimit = 5, WindowMinutes = 15 };

    // Authenticated endpoints — partitioned by user id.
    public RateLimitPolicy Media { get; set; } = new() { PermitLimit = 20, WindowMinutes = 60 };

    // Global ceilings applied to everything else: per user when authenticated, per IP when anonymous.
    public RateLimitPolicy Authenticated { get; set; } = new() { PermitLimit = 300, WindowMinutes = 1 };
    public RateLimitPolicy Anonymous { get; set; } = new() { PermitLimit = 60, WindowMinutes = 1 };
}

public class RateLimitPolicy
{
    public int PermitLimit { get; set; }
    public int WindowMinutes { get; set; }

    public TimeSpan Window => TimeSpan.FromMinutes(WindowMinutes);
}
