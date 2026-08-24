using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.People.DTOs;

namespace FreelanceApp.Application.Interfaces.Services;

public interface IPeopleService
{
    Task<PagedResult<PersonDto>> SearchAsync(Guid currentUserId, PeopleQuery query, CancellationToken ct = default);
}
