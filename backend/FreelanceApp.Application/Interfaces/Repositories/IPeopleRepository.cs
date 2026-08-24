using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.People.DTOs;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface IPeopleRepository
{
    /// <summary>
    /// Paginated user directory. Excludes <paramref name="currentUserId"/> and
    /// projects each row's connection status against the current user in a SINGLE
    /// query (no per-row round-trip). <paramref name="search"/> is already trimmed;
    /// null/empty = everyone. <paramref name="page"/>/<paramref name="pageSize"/>
    /// are assumed already validated/clamped by the caller.
    /// </summary>
    Task<PagedResult<PersonDto>> SearchAsync(
        Guid currentUserId, string? search, int page, int pageSize, CancellationToken ct = default);
}
