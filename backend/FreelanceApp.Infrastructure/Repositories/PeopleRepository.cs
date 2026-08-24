using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.People.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace FreelanceApp.Infrastructure.Repositories;

public class PeopleRepository : IPeopleRepository
{
    private readonly AppDbContext _context;

    public PeopleRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<PagedResult<PersonDto>> SearchAsync(
        Guid currentUserId, string? search, int page, int pageSize, CancellationToken ct = default)
    {
        // Users LEFT JOIN Profiles — profile abhi na bana ho to bhi user directory mein aaye.
        var baseQuery =
            from u in _context.Users
            where u.Id != currentUserId
            join p in _context.Profiles on u.Id equals p.UserId into pg
            from p in pg.DefaultIfEmpty()
            select new { User = u, Profile = p };

        // Case-insensitive match — name ya headline par. lower(x) LIKE '%s%' banta hai
        // Postgres par (case-insensitive), aur provider-agnostic bhi hai (testable).
        if (!string.IsNullOrEmpty(search))
        {
            var term = search.ToLower();
            baseQuery = baseQuery.Where(x =>
                x.User.FullName.ToLower().Contains(term) ||
                (x.Profile != null && x.Profile.Headline != null &&
                 x.Profile.Headline.ToLower().Contains(term)));
        }

        var totalCount = await baseQuery.CountAsync(ct);

        // Stable order: name asc, then Id — duplicate names pagination ko todein na.
        // connectionStatus har row ke liye correlated subquery se aata hai; poora page
        // ek hi SQL statement mein resolve hota hai (no N+1). Priority: Accepted >
        // PendingOutgoing > PendingIncoming > None. Rejected rows "None" hi rehti hain.
        var items = await baseQuery
            .OrderBy(x => x.User.FullName)
            .ThenBy(x => x.User.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(x => new PersonDto
            {
                UserId = x.User.Id,
                FullName = x.User.FullName,
                Headline = x.Profile != null ? x.Profile.Headline : null,
                PhotoUrl = x.Profile != null ? x.Profile.ProfilePhotoUrl : null,
                ConnectionStatus =
                    _context.Connections.Any(c => c.Status == ConnectionStatus.Accepted &&
                        ((c.RequesterId == currentUserId && c.ReceiverId == x.User.Id) ||
                         (c.RequesterId == x.User.Id && c.ReceiverId == currentUserId)))
                        ? "Connected"
                    : _context.Connections.Any(c => c.Status == ConnectionStatus.Pending &&
                        c.RequesterId == currentUserId && c.ReceiverId == x.User.Id)
                        ? "PendingOutgoing"
                    : _context.Connections.Any(c => c.Status == ConnectionStatus.Pending &&
                        c.RequesterId == x.User.Id && c.ReceiverId == currentUserId)
                        ? "PendingIncoming"
                    : "None"
            })
            .ToListAsync(ct);

        return new PagedResult<PersonDto>
        {
            Items = items,
            Page = page,
            PageSize = pageSize,
            TotalCount = totalCount
        };
    }
}
