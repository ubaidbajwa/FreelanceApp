using FreelanceApp.Domain.Entities;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface IKycRepository
{
    Task<IdentityVerification?> GetByUserIdAsync(Guid userId);
    Task<IdentityVerification?> GetByIdAsync(Guid id);
    Task<List<IdentityVerification>> GetPendingReviewAsync();
    Task AddAsync(IdentityVerification verification);
    Task SaveChangesAsync();
}