using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace FreelanceApp.Infrastructure.Repositories;

public class ProfileRepository : IProfileRepository
{
    private readonly AppDbContext _context;

    public ProfileRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Profile?> GetByUserIdAsync(Guid userId)
    {
        return await _context.Profiles
            .Include(p => p.Experiences)
            .FirstOrDefaultAsync(p => p.UserId == userId);
    }

    public async Task<bool> UsernameExistsAsync(string username, Guid? excludeUserId = null)
    {
        var query = _context.Profiles.Where(p => p.Username == username);

        if (excludeUserId != null)
            query = query.Where(p => p.UserId != excludeUserId);

        return await query.AnyAsync();
    }

    public async Task AddAsync(Profile profile)
    {
        await _context.Profiles.AddAsync(profile);
    }

    public async Task<Experience?> GetExperienceByIdAsync(Guid id)
    {
        return await _context.Experiences.FirstOrDefaultAsync(e => e.Id == id);
    }

    public async Task AddExperienceAsync(Experience experience)
    {
        await _context.Experiences.AddAsync(experience);
    }

    public void RemoveExperience(Experience experience)
    {
        _context.Experiences.Remove(experience);
    }

    public async Task SaveChangesAsync()
    {
        try
        {
            await _context.SaveChangesAsync();
        }
        // Race condition: service ke availability-check ke baad, save se pehle,
        // koi aur wahi username claim kar le → Postgres unique violation (23505).
        // Isay clean 409 ProblemDetails mein translate karte hain.
        catch (DbUpdateException ex) when (
            ex.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation } pg &&
            pg.ConstraintName == "IX_Profiles_Username")
        {
            throw new ConflictException("Username already taken.");
        }
    }
}
