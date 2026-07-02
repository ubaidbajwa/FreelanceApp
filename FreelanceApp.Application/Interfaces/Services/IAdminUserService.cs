namespace FreelanceApp.Application.Interfaces.Services;

public interface IAdminUserService
{
    Task<Guid> CreateAdminAsync(string email, string password, string fullName);
}
