using StackExchange.Redis;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Infrastructure.Repositories;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using FluentValidation;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using FluentValidation.AspNetCore;
using FreelanceApp.Application.Features.Auth.Validators;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Infrastructure.Services;
using FreelanceApp.Application.Features.Auth.Services;
using FreelanceApp.Api.ExceptionHandlers;
using FreelanceApp.Application.Common.Settings;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using FreelanceApp.Api.Services;
using FreelanceApp.Api.Hubs;
using Microsoft.AspNetCore.SignalR;
using FreelanceApp.Application.Features.Kyc.Services;
using FreelanceApp.Application.Features.Profiles.Services;
using FreelanceApp.Application.Features.Connections.Services;
using FreelanceApp.Application.Features.Network.Services;
using FreelanceApp.Application.Features.People.Services;
using FreelanceApp.Application.Features.Messaging.Services;
using System.Threading.RateLimiting;
using System.Diagnostics;
using System.Globalization;
using Microsoft.AspNetCore.Mvc;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.

builder.Services.AddControllers();
// Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
// Database connection setup
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// Redis connection (singleton — manages internal connection pool)
builder.Services.AddSingleton<IConnectionMultiplexer>(sp =>
{
    var connectionString = builder.Configuration.GetConnectionString("Redis")!;
    return ConnectionMultiplexer.Connect(connectionString);
});

// Refresh token service
builder.Services.AddScoped<IRefreshTokenService, RedisRefreshTokenService>();

// Repository registrations
builder.Services.AddScoped<IUserRepository, UserRepository>();

builder.Services.AddScoped<IEmailOtpRepository, EmailOtpRepository>();


// AuthService registration
builder.Services.AddScoped<IAuthService, AuthService>();

// Captcha — options bound from "Captcha" section (secrets via user-secrets /
// env vars, NOT appsettings). Typed HttpClient gives us a pooled handler +
// a 5s ceiling on the siteverify round-trip.
builder.Services.Configure<CaptchaOptions>(
    builder.Configuration.GetSection(CaptchaOptions.SectionName));

builder.Services.AddHttpClient<ICaptchaVerifier, GoogleCaptchaVerifier>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(5);
});

// Google Sign-In — accepted client IDs bound from "GoogleAuth" section.
builder.Services.Configure<GoogleAuthSettings>(
    builder.Configuration.GetSection(GoogleAuthSettings.SectionName));
builder.Services.AddScoped<IGoogleTokenVerifier, GoogleTokenVerifier>();

// Global exception handling (RFC 7807 ProblemDetails)
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();

// Disable automatic claim mapping (preserve "sub" as-is)
JwtSecurityTokenHandler.DefaultInboundClaimTypeMap.Clear();

// JWT Settings binding
builder.Services.Configure<JwtSettings>(
    builder.Configuration.GetSection(JwtSettings.SectionName));

// JWT Token Service
builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();

// Email Settings binding (Mailtrap)
builder.Services.Configure<EmailSettings>(
    builder.Configuration.GetSection(EmailSettings.SectionName));

// Email Service (scoped — new SmtpClient per call; used by EmailBackgroundService via scope)
builder.Services.AddScoped<IEmailService, SmtpEmailService>();

// Email queue + background sender — singleton channel, BackgroundService drains it.
// Requests enqueue and return immediately; SMTP runs off the request thread.
builder.Services.AddSingleton<EmailQueueService>();
builder.Services.AddSingleton<IEmailQueue>(sp => sp.GetRequiredService<EmailQueueService>());
builder.Services.AddHostedService<EmailBackgroundService>();

// OTP Service
builder.Services.AddScoped<IOtpService, OtpService>();

// Cloudinary Settings binding
builder.Services.Configure<CloudinarySettings>(
    builder.Configuration.GetSection(CloudinarySettings.SectionName));

builder.Services.Configure<GoogleVisionSettings>(
    builder.Configuration.GetSection(GoogleVisionSettings.SectionName));

builder.Services.AddSingleton<IOcrService, GoogleVisionOcrService>();

// AWS Rekognition Settings binding
builder.Services.Configure<AwsRekognitionSettings>(
    builder.Configuration.GetSection(AwsRekognitionSettings.SectionName));

builder.Services.AddSingleton<IFaceMatchService, AwsRekognitionFaceMatchService>();  


// Image Storage Service
builder.Services.AddScoped<IImageStorageService, CloudinaryImageService>();
// Chat media (image/video with full metadata) — SAME Cloudinary service, second interface, one integration.
builder.Services.AddScoped<IMediaStorageService, CloudinaryImageService>();

builder.Services.AddScoped<IKycRepository, KycRepository>();
builder.Services.AddScoped<IKycService, KycService>();

// Profile module
builder.Services.AddScoped<IProfileRepository, ProfileRepository>();
builder.Services.AddScoped<IProfileService, ProfileService>();

// Connections module
builder.Services.AddScoped<IConnectionRepository, ConnectionRepository>();
builder.Services.AddScoped<IConnectionService, ConnectionService>();

// Network module
builder.Services.AddScoped<INetworkService, NetworkService>();

// Suggestions module
builder.Services.Configure<SuggestionSettings>(
    builder.Configuration.GetSection(SuggestionSettings.SectionName));

builder.Services.AddScoped<ISuggestionRepository, SuggestionRepository>();
builder.Services.AddScoped<ISuggestionScorer, WeightedSuggestionScorer>();

// Cache: NoOp by default (CacheSeconds == 0); swap to Redis by setting CacheSeconds > 0
var suggestionCacheSeconds = builder.Configuration
    .GetSection(SuggestionSettings.SectionName)
    .GetValue<int>(nameof(SuggestionSettings.CacheSeconds));
if (suggestionCacheSeconds > 0)
    builder.Services.AddScoped<ISuggestionCache, RedisSuggestionCache>();
else
    builder.Services.AddScoped<ISuggestionCache, NoOpSuggestionCache>();

builder.Services.AddScoped<ISuggestionService, SuggestionService>();

// Follow module
builder.Services.AddScoped<IFollowRepository, FollowRepository>();
builder.Services.AddScoped<IFollowSuggestionScorer, WeightedFollowSuggestionScorer>();
builder.Services.AddScoped<IFollowService, FollowService>();

// Messaging module (M1)
builder.Services.AddScoped<IConversationRepository, ConversationRepository>();
builder.Services.AddScoped<IChatService, ChatService>();

// Real-time chat (SignalR is part of the ASP.NET Core shared framework — no NuGet package).
builder.Services.AddSignalR();
// Target users by id across every device — never a hand-rolled connectionId map.
builder.Services.AddSingleton<IUserIdProvider, ChatUserIdProvider>();
// SignalR adapter for the IChatNotifier seam. Lives in Api (transport concern), not Infrastructure.
builder.Services.AddScoped<IChatNotifier, SignalRChatNotifier>();

// People directory module
builder.Services.AddScoped<IPeopleRepository, PeopleRepository>();
builder.Services.AddScoped<IPeopleService, PeopleService>();
builder.Services.AddScoped<IAdminKycService, AdminKycService>();
builder.Services.AddScoped<IAdminUserService, AdminUserService>();

// Admin Settings binding
builder.Services.Configure<AdminSettings>(
    builder.Configuration.GetSection(AdminSettings.SectionName));

// JWT Authentication
var jwtSettings = builder.Configuration
    .GetSection(JwtSettings.SectionName)
    .Get<JwtSettings>()!;

// Fail fast if the signing key isn't configured (e.g. empty in appsettings.json
// and no user-secrets/env override). An empty key makes every token invalid.
if (string.IsNullOrWhiteSpace(jwtSettings.Secret))
    throw new InvalidOperationException(
        "JwtSettings:Secret is not configured. Set it via user-secrets or environment variables.");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        // .NET 8 uses JsonWebTokenHandler (not JwtSecurityTokenHandler), so the
        // DefaultInboundClaimTypeMap.Clear() above doesn't reach it. Without this,
        // "sub" gets remapped to ClaimTypes.NameIdentifier and the SecurityStamp
        // check below fails every token with "Missing required claims".
        options.MapInboundClaims = false;

        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtSettings.Issuer,
            ValidAudience = jwtSettings.Audience,
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(jwtSettings.Secret))
        };

        // ⬇️ NAYA — SecurityStamp validation
        options.Events = new JwtBearerEvents
        {
            // WebSocket handshakes can't send an Authorization header, so SignalR clients pass
            // the JWT as ?access_token=. Lift it onto context.Token ONLY for /hubs paths — every
            // other validation rule (key, issuer, audience, lifetime, SecurityStamp) still runs.
            OnMessageReceived = context =>
            {
                var accessToken = context.Request.Query["access_token"];
                var path = context.HttpContext.Request.Path;
                if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs"))
                    context.Token = accessToken;

                return Task.CompletedTask;
            },

            OnTokenValidated = async context =>
            {
                // Get the SecurityStamp claim from token
                var tokenStamp = context.Principal?.FindFirst("security_stamp")?.Value;
                var userIdClaim = context.Principal?.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;

                if (string.IsNullOrEmpty(tokenStamp) || string.IsNullOrEmpty(userIdClaim))
                {
                    context.Fail("Missing required claims");
                    return;
                }

                if (!Guid.TryParse(userIdClaim, out var userId) ||
                    !Guid.TryParse(tokenStamp, out var tokenStampGuid))
                {
                    context.Fail("Invalid claim format");
                    return;
                }

                // Get current SecurityStamp from database
                var userRepo = context.HttpContext.RequestServices
                    .GetRequiredService<IUserRepository>();

                var currentStamp = await userRepo.GetSecurityStampAsync(userId);

                if (currentStamp == null)
                {
                    context.Fail("User no longer exists");
                    return;
                }

                if (currentStamp != tokenStampGuid)
                {
                    context.Fail("Session revoked. Please login again.");
                    return;
                }

                // ✅ Stamp matches — request continues
            }
        };
        // ⬆️ NAYA END
    });

// HttpContext access (required for CurrentUserService)
builder.Services.AddHttpContextAccessor();

// Current user service (Clean Architecture pattern)
builder.Services.AddScoped<ICurrentUserService, CurrentUserService>();

// Authorization with custom policies
builder.Services.AddAuthorization(options =>
{
    // global identity-verification policy — claim name must match the one issued in JwtTokenService ("identity_verified")
    options.AddPolicy("IdentityVerified", policy =>
    policy.RequireClaim("identity_verified", "true"));

    // LEGACY placeholders — these gate on primary_role (default experience), which is
    // NOT a permission boundary. New work-action endpoints (apply, post job) must
    // authorize via CAPABILITIES (profile completion), not these. Kept only so existing
    // demo endpoints keep working after the claim rename (role → primary_role).
    options.AddPolicy("FreelancerOnly", policy =>
        policy.RequireClaim("primary_role", "Freelancer"));

    options.AddPolicy("ClientOnly", policy =>
        policy.RequireClaim("primary_role", "Client"));

    // AdminOnly is a genuine platform role (not freelancer/client) — claim-based authz here is fine.
    options.AddPolicy("AdminOnly", policy =>
        policy.RequireClaim("primary_role", "Admin"));
});

// FluentValidation registration
builder.Services.AddValidatorsFromAssemblyContaining<RegisterRequestValidator>();
builder.Services.AddFluentValidationAutoValidation();

// Service registrations
builder.Services.AddScoped<IPasswordHasher, BCryptPasswordHasher>();

// CORS setup — web frontends ke liye (Flutter mobile ko CORS lagta hi nahi,
// ye sirf browser-based clients par apply hota hai)
// Production: Cors:AllowedOrigins mein frontend domains set karein
// (e.g. ["https://app.example.com"]). Origins configure na hon toh
// production mein koi cross-origin request allow nahi hoti.
var allowedOrigins = builder.Configuration
    .GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", policy =>
    {
        if (allowedOrigins.Length > 0)
        {
            policy.WithOrigins(allowedOrigins)
                  .AllowAnyMethod()
                  .AllowAnyHeader();
        }
        else if (builder.Environment.IsDevelopment())
        {
            // Dev-only fallback: local testing without origin config
            // TODO: SignalR from a browser needs .AllowCredentials(), which is INCOMPATIBLE
            // with .AllowAnyOrigin(). Before any web client or production deploy, replace this
            // with a named-origin policy: .WithOrigins(<web origins>).AllowCredentials().
            // The Flutter mobile client is unaffected (WebSocket, no CORS).
            policy.AllowAnyOrigin()
                  .AllowAnyMethod()
                  .AllowAnyHeader();
        }
    });
});

// Rate limiting — brute-force / abuse protection. Limits are bound from the "RateLimiting" section
// (RateLimitSettings) so they can be tuned without a redeploy. Unauthenticated endpoints partition
// by client IP; authenticated ones by user id — an office/university behind one NAT must not throttle
// each other, and that is exactly Skillora's user base. Fixed window (a hard ceiling per period),
// never token bucket. Rejections are RFC 7807 problem+json with a Retry-After header, matching
// GlobalExceptionHandler. The SignalR hub is never limited (see the global limiter below).
var rateLimitSettings = builder.Configuration
    .GetSection(RateLimitSettings.SectionName)
    .Get<RateLimitSettings>() ?? new RateLimitSettings();
builder.Services.Configure<RateLimitSettings>(
    builder.Configuration.GetSection(RateLimitSettings.SectionName));

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.OnRejected = async (context, ct) =>
    {
        var response = context.HttpContext.Response;

        // Retry-After: fixed-window limiters expose the remaining window as metadata. Surface it as
        // the standard header so a well-behaved client backs off exactly as long as it must.
        int? retryAfterSeconds = null;
        if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
        {
            retryAfterSeconds = (int)Math.Ceiling(retryAfter.TotalSeconds);
            response.Headers.RetryAfter = retryAfterSeconds.Value.ToString(CultureInfo.InvariantCulture);
        }

        // RFC 7807 body, same shape GlobalExceptionHandler emits for every other error.
        var problem = new ProblemDetails
        {
            Status = StatusCodes.Status429TooManyRequests,
            Title = "Too Many Requests",
            Detail = retryAfterSeconds is int s
                ? $"Rate limit exceeded. Please retry after {s} seconds."
                : "Rate limit exceeded. Please slow down and try again shortly.",
            Type = "https://httpstatuses.com/429",
            Instance = context.HttpContext.Request.Path
        };
        problem.Extensions["traceId"] = Activity.Current?.Id ?? context.HttpContext.TraceIdentifier;

        response.StatusCode = StatusCodes.Status429TooManyRequests;
        response.ContentType = "application/problem+json";
        await response.WriteAsJsonAsync(problem, ct);
    };

    // Pre-auth endpoints — partitioned by client IP (no user identity yet).
    RateLimitPartition<string> ByIp(HttpContext ctx, RateLimitPolicy p) =>
        RateLimitPartition.GetFixedWindowLimiter(
            ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = p.PermitLimit, Window = p.Window, QueueLimit = 0 });

    // Authenticated endpoints — partitioned by user id (falls back to IP if the claim is missing).
    RateLimitPartition<string> ByUser(HttpContext ctx, RateLimitPolicy p) =>
        RateLimitPartition.GetFixedWindowLimiter(
            ctx.User.FindFirst("sub")?.Value ?? ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = p.PermitLimit, Window = p.Window, QueueLimit = 0 });

    options.AddPolicy("login", ctx => ByIp(ctx, rateLimitSettings.Login));
    options.AddPolicy("register", ctx => ByIp(ctx, rateLimitSettings.Register));
    options.AddPolicy("forgot-password", ctx => ByIp(ctx, rateLimitSettings.ForgotPassword));
    options.AddPolicy("otp", ctx => ByIp(ctx, rateLimitSettings.Otp));   // verify / resend OTP
    options.AddPolicy("media", ctx => ByUser(ctx, rateLimitSettings.Media));

    // Global ceiling on everything else — per user when authenticated, per IP when anonymous. The
    // SignalR hub is exempt: a long-lived WebSocket is ONE connection, not repeated requests, and
    // throttling reconnects would break recovery on flaky networks exactly when it matters most.
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx =>
    {
        if (ctx.Request.Path.StartsWithSegments("/hubs"))
            return RateLimitPartition.GetNoLimiter("hub");

        var userId = ctx.User.FindFirst("sub")?.Value;
        return userId is not null
            ? RateLimitPartition.GetFixedWindowLimiter($"user:{userId}",
                _ => new FixedWindowRateLimiterOptions
                { PermitLimit = rateLimitSettings.Authenticated.PermitLimit, Window = rateLimitSettings.Authenticated.Window, QueueLimit = 0 })
            : RateLimitPartition.GetFixedWindowLimiter($"ip:{ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown"}",
                _ => new FixedWindowRateLimiterOptions
                { PermitLimit = rateLimitSettings.Anonymous.PermitLimit, Window = rateLimitSettings.Anonymous.Window, QueueLimit = 0 });
    });
});

var app = builder.Build();

// Exception handler MUST be first in pipeline
app.UseExceptionHandler();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Dev mein off — phone http se aata hai (no trusted cert on phone)
// Production mein on — https enforce hoga
if (!app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}

// 1. Pehle Routing aayegi
app.UseRouting();

// 2. Phir CORS aayega
app.UseCors("AllowFrontend");

// 3. Phir Authentication aayegi
app.UseAuthentication();

// 4. Rate limiter — AFTER authentication so authenticated policies (media, global ceiling) can
//    partition by user id (User is populated only after UseAuthentication). Pre-auth policies
//    (login/register/otp) partition by IP and are unaffected by the ordering.
app.UseRateLimiter();

// 5. Phir Authorization aayegi
app.UseAuthorization();

app.MapControllers();

// Chat hub — after authN/authZ so the [Authorize] hub sees the authenticated user.
// JWT arrives via ?access_token= on the handshake (see OnMessageReceived above).
app.MapHub<ChatHub>("/hubs/chat");

app.Run();