using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.People.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;

namespace FreelanceApp.Application.Features.People.Services;

public class PeopleService(IPeopleRepository peopleRepository) : IPeopleService
{
    public const int DefaultPageSize = 20;
    public const int MaxPageSize = 50;

    public Task<PagedResult<PersonDto>> SearchAsync(
        Guid currentUserId, PeopleQuery query, CancellationToken ct = default)
    {
        // Clamp (not reject): pageSize 1..50, page >= 1 — koi poori table na kheench sake.
        var page = query.Page < 1 ? 1 : query.Page;
        var pageSize = query.PageSize < 1 ? DefaultPageSize
                     : query.PageSize > MaxPageSize ? MaxPageSize
                     : query.PageSize;

        var search = string.IsNullOrWhiteSpace(query.Search) ? null : query.Search.Trim();

        return peopleRepository.SearchAsync(currentUserId, search, page, pageSize, ct);
    }
}
