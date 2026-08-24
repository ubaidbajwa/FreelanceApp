namespace FreelanceApp.Application.Common.Models;

/// <summary>
/// Small reusable pagination envelope. First paged endpoint in the codebase —
/// keep the shape generic so later list endpoints reuse it.
/// </summary>
public class PagedResult<T>
{
    public IReadOnlyList<T> Items { get; set; } = [];
    public int Page { get; set; }
    public int PageSize { get; set; }
    public int TotalCount { get; set; }

    public int TotalPages => PageSize > 0 ? (int)Math.Ceiling(TotalCount / (double)PageSize) : 0;
    public bool HasNextPage => Page < TotalPages;
}
