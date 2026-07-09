using FreelanceApp.Application.Interfaces.Services;

namespace FreelanceApp.Infrastructure.Services;

public class BCryptPasswordHasher : IPasswordHasher
{
    private const int WorkFactor = 13;

    public string HashPassword(string plainPassword)
    {
        return BCrypt.Net.BCrypt.HashPassword(plainPassword, WorkFactor);
    }

    public bool VerifyPassword(string plainPassword, string hashedPassword)
    {
        return BCrypt.Net.BCrypt.Verify(plainPassword, hashedPassword);
    }

    public bool NeedsRehash(string hashedPassword)
    {
        return BCrypt.Net.BCrypt.PasswordNeedsRehash(hashedPassword, WorkFactor);
    }
}