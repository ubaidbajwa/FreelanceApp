using FreelanceApp.Domain.Entities;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface IProfileRepository
{
    Task<Profile?> GetByUserIdAsync(Guid userId);           // Experiences included
    Task<bool> UsernameExistsAsync(string username, Guid? excludeUserId = null);
    Task AddAsync(Profile profile);
    Task<Experience?> GetExperienceByIdAsync(Guid id);
    Task AddExperienceAsync(Experience experience);
    void RemoveExperience(Experience experience);
    Task SaveChangesAsync();
}
