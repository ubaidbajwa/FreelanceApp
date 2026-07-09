namespace FreelanceApp.Application.Interfaces.Services;

public interface IPasswordHasher
{
    string HashPassword(string plainPassword);
    bool VerifyPassword(string plainPassword, string hashedPassword);
    bool NeedsRehash(string hashedPassword); 
}