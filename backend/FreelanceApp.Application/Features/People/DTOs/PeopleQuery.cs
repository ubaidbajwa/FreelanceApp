namespace FreelanceApp.Application.Features.People.DTOs;

// Directory query params. pageSize service mein max 50 pe clamp hoti hai.
public class PeopleQuery
{
    public string? Search { get; set; }
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 20;
}
