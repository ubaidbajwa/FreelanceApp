using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Network.DTOs;

namespace FreelanceApp.Application.Interfaces.Services;

// Cache key: userId + page + pageSize.
// Invalidation is intentionally out of scope for this slice — a short TTL (SuggestionSettings.CacheSeconds)
// is the deliberate invalidation strategy. Stale suggestions auto-expire; no event-driven invalidation.
public interface ISuggestionCache
{
    Task<PagedResult<SuggestionResponse>?> GetAsync(Guid userId, int page, int pageSize, CancellationToken ct);
    Task SetAsync(Guid userId, int page, int pageSize, PagedResult<SuggestionResponse> result, int ttlSeconds, CancellationToken ct);
}
