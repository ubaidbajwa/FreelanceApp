using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Network.DTOs;

namespace FreelanceApp.Application.Interfaces.Services;

public interface ISuggestionService
{
    Task<PagedResult<SuggestionResponse>> GetSuggestionsAsync(
        Guid meId, int page, int pageSize, CancellationToken ct = default);

    Task DismissAsync(Guid meId, Guid dismissedUserId, CancellationToken ct = default);
    Task UndismissAsync(Guid meId, Guid dismissedUserId, CancellationToken ct = default);
}
