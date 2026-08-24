using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface IUserRepository
{
    Task<User?> GetByIdAsync(Guid id);
    Task<User?> GetByEmailAsync(string email);

    // Matches a social account by provider + the provider's stable user id
    // (e.g. Google's "sub"). Returns null when no such account exists yet.
    Task<User?> GetByExternalIdAsync(AuthProvider provider, string externalId);

    Task<bool> EmailExistsAsync(string email);
    Task AddAsync(User user);
    Task SaveChangesAsync();
    Task<Guid?> GetSecurityStampAsync(Guid userId);

}