using FreelanceApp.Domain.Entities;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface IUserRepository
{
    Task<User?> GetByIdAsync(Guid id);
    Task<User?> GetByEmailAsync(string email);
    Task<bool> EmailExistsAsync(string email);
    Task AddAsync(User user);
    Task SaveChangesAsync();
    Task<Guid?> GetSecurityStampAsync(Guid userId);

}