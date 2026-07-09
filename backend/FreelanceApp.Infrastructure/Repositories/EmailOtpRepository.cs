using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace FreelanceApp.Infrastructure.Repositories;

public class EmailOtpRepository : IEmailOtpRepository
{
    private readonly AppDbContext _context;

    public EmailOtpRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<EmailOtp?> GetLatestActiveOtpAsync(Guid userId, OtpPurpose purpose)
    {
        return await _context.EmailOtps
            .Where(o => o.UserId == userId
                     && o.Purpose == purpose
                     && !o.IsUsed)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync();
    }

    public async Task<EmailOtp?> GetLatestOtpAsync(Guid userId, OtpPurpose purpose)
    {
        return await _context.EmailOtps
            .Where(o => o.UserId == userId && o.Purpose == purpose)
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync();
    }
}