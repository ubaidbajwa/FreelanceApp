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
using FreelanceApp.Application.Features.Kyc.Services;
using System.Threading.RateLimiting;

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

// Email Service
builder.Services.AddScoped<IEmailService, SmtpEmailService>();

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

builder.Services.AddScoped<IKycRepository, KycRepository>();
builder.Services.AddScoped<IKycService, KycService>();
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

    // Future policies (placeholders for next phases)
    options.AddPolicy("FreelancerOnly", policy =>
        policy.RequireClaim("role", "Freelancer"));

    options.AddPolicy("ClientOnly", policy =>
        policy.RequireClaim("role", "Client"));

    options.AddPolicy("AdminOnly", policy =>
        policy.RequireClaim("role", "Admin"));
});

// FluentValidation registration
builder.Services.AddValidatorsFromAssemblyContaining<RegisterRequestValidator>();
builder.Services.AddFluentValidationAutoValidation();

// Service registrations
builder.Services.AddScoped<IPasswordHasher, BCryptPasswordHasher>();

// CORS setup — Flutter aur web panel ke liye
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// Rate limiting — brute-force protection on auth endpoints
// Per-IP fixed window: 10 requests/minute covers a legit signup flow
// (register → verify-email → resend-otp) while blocking credential stuffing.
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.OnRejected = async (context, ct) =>
    {
        context.HttpContext.Response.ContentType = "application/problem+json";
        await context.HttpContext.Response.WriteAsJsonAsync(new
        {
            status = 429,
            title = "Too Many Requests",
            detail = "Too many attempts. Please wait a minute and try again."
        }, ct);
    };

    options.AddPolicy("auth", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            }));
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

app.UseHttpsRedirection();

// 1. Pehle Routing aayegi
app.UseRouting();

// 2. Rate limiter — routing ke baad taake endpoint policies match ho sakein
app.UseRateLimiter();

// 3. Phir CORS aayega
app.UseCors("AllowFrontend");

// 4. Phir Authentication aayegi
app.UseAuthentication();

// 5. Phir Authorization aayegi
app.UseAuthorization();

app.MapControllers();

app.Run();