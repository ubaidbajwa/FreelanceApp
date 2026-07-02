using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace FreelanceApp.Infrastructure.Repositories;

public class KycRepository : IKycRepository
{
    private readonly AppDbContext _context;

    public KycRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<IdentityVerification?> GetByUserIdAsync(Guid userId)
    {
        return await _context.IdentityVerifications
            .Where(v => v.UserId == userId)
            .OrderByDescending(v => v.CreatedAt)
            .FirstOrDefaultAsync();
    }

    public async Task<IdentityVerification?> GetByIdAsync(Guid id)
    {
        return await _context.IdentityVerifications
            .Include(v => v.User)
            .FirstOrDefaultAsync(v => v.Id == id);
    }

    public async Task<List<IdentityVerification>> GetPendingReviewAsync()
    {
        return await _context.IdentityVerifications
            .Include(v => v.User)
            .Where(v => v.Status == KycStatus.UnderReview)
            .OrderBy(v => v.CreatedAt)   // oldest first — FIFO review queue
            .ToListAsync();
    }

    public async Task AddAsync(IdentityVerification verification)
    {
        await _context.IdentityVerifications.AddAsync(verification);
    }

    public async Task SaveChangesAsync()
    {
        await _context.SaveChangesAsync();
    }
}