using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace FreelanceApp.Infrastructure.Repositories;

public class UserRepository : IUserRepository
{
    private readonly AppDbContext _context;

    public UserRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<User?> GetByIdAsync(Guid id)
    {
        return await _context.Users.FindAsync(id);
    }

    public async Task<User?> GetByEmailAsync(string email)
    {
        return await _context.Users
            .FirstOrDefaultAsync(u => u.Email == email);
    }

    public async Task<bool> EmailExistsAsync(string email)
    {
        return await _context.Users
            .AnyAsync(u => u.Email == email);
    }

    public async Task AddAsync(User user)
    {
        await _context.Users.AddAsync(user);
    }

    public async Task SaveChangesAsync()
    {
        await _context.SaveChangesAsync();
    }

    public async Task<Guid?> GetSecurityStampAsync(Guid userId)
    {
        var stamp = await _context.Users
            .Where(u => u.Id == userId)
            .Select(u => (Guid?)u.SecurityStamp)
            .FirstOrDefaultAsync();

        return stamp;
    }
}