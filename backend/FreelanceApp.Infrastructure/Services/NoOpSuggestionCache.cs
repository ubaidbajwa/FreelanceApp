using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Interfaces.Services;

namespace FreelanceApp.Infrastructure.Services;

// Default implementation: always returns null (cache miss), never stores.
// Active when SuggestionSettings.CacheSeconds == 0.
public sealed class NoOpSuggestionCache : ISuggestionCache
{
    public Task<PagedResult<SuggestionResponse>?> GetAsync(
        Guid userId, int page, int pageSize, CancellationToken ct) =>
        Task.FromResult<PagedResult<SuggestionResponse>?>(null);

    public Task SetAsync(
        Guid userId, int page, int pageSize,
        PagedResult<SuggestionResponse> result, int ttlSeconds, CancellationToken ct) =>
        Task.CompletedTask;
}
