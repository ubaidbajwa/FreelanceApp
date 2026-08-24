using System.Text.Json;
using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Interfaces.Services;
using StackExchange.Redis;

namespace FreelanceApp.Infrastructure.Services;

// Active when SuggestionSettings.CacheSeconds > 0.
// Invalidation is intentionally out of scope for this slice — a short TTL is the deliberate
// strategy. Suggestions naturally refresh on expiry without event-driven invalidation on
// connection changes, skill edits, or dismissals.
public sealed class RedisSuggestionCache(IConnectionMultiplexer redis) : ISuggestionCache
{
    private IDatabase Db => redis.GetDatabase();
    private const string KeyPrefix = "suggestions:v1:";

    private static string Key(Guid userId, int page, int pageSize) =>
        $"{KeyPrefix}{userId}:{page}:{pageSize}";

    public async Task<PagedResult<SuggestionResponse>?> GetAsync(
        Guid userId, int page, int pageSize, CancellationToken ct)
    {
        var value = await Db.StringGetAsync(Key(userId, page, pageSize));
        if (value.IsNullOrEmpty) return null;
        return JsonSerializer.Deserialize<PagedResult<SuggestionResponse>>(value.ToString());
    }

    public async Task SetAsync(
        Guid userId, int page, int pageSize,
        PagedResult<SuggestionResponse> result, int ttlSeconds, CancellationToken ct)
    {
        var json = JsonSerializer.Serialize(result);
        await Db.StringSetAsync(Key(userId, page, pageSize), json, TimeSpan.FromSeconds(ttlSeconds));
    }
}
