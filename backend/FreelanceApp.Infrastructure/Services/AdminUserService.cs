using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging;

namespace FreelanceApp.Infrastructure.Services;

public class AdminUserService(
    IUserRepository userRepository,
    IPasswordHasher passwordHasher,
    ILogger<AdminUserService> logger) : IAdminUserService
{
    public async Task<Guid> CreateAdminAsync(string email, string password, string fullName)
    {
        var normalizedEmail = email.ToLower().Trim();

        if (await userRepository.EmailExistsAsync(normalizedEmail))
            throw new ConflictException("Email is already registered.");

        var admin = new User
        {
            Id = Guid.NewGuid(),
            Email = normalizedEmail,
            PasswordHash = passwordHasher.HashPassword(password),
            FullName = fullName.Trim(),
            Role = UserRole.Admin,
            IsIdentityVerified = true,   // admins skip KYC
            IsEmailVerified = true,      // admins skip OTP verification
            SecurityStamp = Guid.NewGuid(),
            CreatedAt = DateTime.UtcNow
        };

        await userRepository.AddAsync(admin);
        await userRepository.SaveChangesAsync();

        logger.LogInformation("Admin user created | AdminId: {AdminId} | Email: {Email}", admin.Id, admin.Email);

        return admin.Id;
    }
}
