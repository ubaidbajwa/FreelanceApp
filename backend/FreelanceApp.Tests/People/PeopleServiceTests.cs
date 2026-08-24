using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.People.DTOs;
using FreelanceApp.Application.Features.People.Services;
using FreelanceApp.Application.Interfaces.Repositories;

namespace FreelanceApp.Tests.People;

// Service layer sirf clamp/trim karti hai, phir repo ko delegate — un knobs ko
// recording fake ke zariye assert karte hain.
public class PeopleServiceTests
{
    private static readonly Guid Me = Guid.NewGuid();

    [Fact]
    public async Task Search_ClampsPageSize_ToMax50()
    {
        var repo = new RecordingRepository();
        var sut = new PeopleService(repo);

        await sut.SearchAsync(Me, new PeopleQuery { PageSize = 1000 });

        Assert.Equal(PeopleService.MaxPageSize, repo.PageSize);
    }

    [Fact]
    public async Task Search_DefaultsPageSize_WhenNonPositive()
    {
        var repo = new RecordingRepository();
        var sut = new PeopleService(repo);

        await sut.SearchAsync(Me, new PeopleQuery { PageSize = 0 });

        Assert.Equal(PeopleService.DefaultPageSize, repo.PageSize);
    }

    [Fact]
    public async Task Search_ClampsPage_ToAtLeast1()
    {
        var repo = new RecordingRepository();
        var sut = new PeopleService(repo);

        await sut.SearchAsync(Me, new PeopleQuery { Page = 0 });

        Assert.Equal(1, repo.Page);
    }

    [Fact]
    public async Task Search_TrimsSearch_AndNullsWhitespace()
    {
        var repo = new RecordingRepository();
        var sut = new PeopleService(repo);

        await sut.SearchAsync(Me, new PeopleQuery { Search = "  alice  " });
        Assert.Equal("alice", repo.Search);

        await sut.SearchAsync(Me, new PeopleQuery { Search = "   " });
        Assert.Null(repo.Search);
    }

    private sealed class RecordingRepository : IPeopleRepository
    {
        public string? Search { get; private set; }
        public int Page { get; private set; }
        public int PageSize { get; private set; }

        public Task<PagedResult<PersonDto>> SearchAsync(
            Guid currentUserId, string? search, int page, int pageSize, CancellationToken ct = default)
        {
            Search = search;
            Page = page;
            PageSize = pageSize;
            return Task.FromResult(new PagedResult<PersonDto> { Page = page, PageSize = pageSize });
        }
    }
}
