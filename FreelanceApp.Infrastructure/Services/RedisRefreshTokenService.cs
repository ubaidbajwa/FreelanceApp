using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using StackExchange.Redis;
using System.Security.Cryptography;

namespace FreelanceApp.Infrastructure.Services;

public class RedisRefreshTokenService(
    IConnectionMultiplexer redis,
    IOptions<JwtSettings> jwtOptions,
    ILogger<RedisRefreshTokenService> logger) : IRefreshTokenService
{
    private readonly JwtSettings _settings = jwtOptions.Value;
    private IDatabase Db => redis.GetDatabase();
    private const string KeyPrefix = "refresh_token:";

    public async Task<string> GenerateAsync(Guid userId, Guid securityStamp)
    {
        // Cryptographically secure random token
        var tokenBytes = RandomNumberGenerator.GetBytes(64);
        var token = Convert.ToBase64String(tokenBytes);

        // Redis mein store: key = token, value = "userId:securityStamp", TTL = 7 days
        // Stamp binding: password reset rotates the stamp, making this token useless
        var key = KeyPrefix + token;
        var expiry = TimeSpan.FromDays(_settings.RefreshTokenExpiryDays);

        await Db.StringSetAsync(key, $"{userId}:{securityStamp}", expiry);

        logger.LogInformation("Refresh token generated for user: {UserId}", userId);
        return token;
    }

    public async Task<RefreshTokenPayload?> ValidateAndConsumeAsync(string refreshToken)
    {
        var key = KeyPrefix + refreshToken;

        // Atomic: get + delete in one operation
        var storedValue = await Db.StringGetDeleteAsync(key);

        if (storedValue.IsNullOrEmpty)
        {
            logger.LogWarning("Invalid or expired refresh token used");
            return null;
        }

        var parts = storedValue.ToString().Split(':');
        if (parts.Length != 2 ||
            !Guid.TryParse(parts[0], out var userId) ||
            !Guid.TryParse(parts[1], out var securityStamp))
        {
            logger.LogError("Corrupt refresh token data in Redis");
            return null;
        }

        logger.LogInformation("Refresh token validated and consumed for user: {UserId}", userId);
        return new RefreshTokenPayload(userId, securityStamp);
    }

    public async Task RevokeAsync(string refreshToken)
    {
        var key = KeyPrefix + refreshToken;
        await Db.KeyDeleteAsync(key);
        logger.LogInformation("Refresh token revoked");
    }

    public Task RevokeAllForUserAsync(Guid userId)
    {
        // Stamp binding makes this a no-op: each refresh token stores the
        // SecurityStamp it was issued under, and AuthService.RefreshAsync rejects
        // any token whose stamp no longer matches the user's current stamp.
        // Rotating the stamp (password reset, admin action) therefore revokes
        // all outstanding refresh tokens without touching Redis.

        logger.LogInformation(
            "RevokeAllForUserAsync called for user: {UserId} | Stamp binding handles invalidation",
            userId);
        return Task.CompletedTask;
    }
}