using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Network.DTOs;

namespace FreelanceApp.Application.Interfaces.Services;

public interface IFollowService
{
    Task FollowAsync(Guid followerId, Guid followeeId, CancellationToken ct = default);
    Task UnfollowAsync(Guid followerId, Guid followeeId, CancellationToken ct = default);
    Task<PagedResult<FollowUserResponse>> GetFollowersAsync(Guid meId, int page, int pageSize, CancellationToken ct = default);
    Task<PagedResult<FollowUserResponse>> GetFollowingAsync(Guid meId, int page, int pageSize, CancellationToken ct = default);
    Task<FollowStatusResponse> GetFollowStatusAsync(Guid meId, Guid targetId, CancellationToken ct = default);
    Task<PagedResult<FollowSuggestionResponse>> GetFollowSuggestionsAsync(Guid meId, int page, int pageSize, CancellationToken ct = default);
    Task DismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, CancellationToken ct = default);
    Task UndismissFollowSuggestionAsync(Guid meId, Guid dismissedUserId, CancellationToken ct = default);
}
