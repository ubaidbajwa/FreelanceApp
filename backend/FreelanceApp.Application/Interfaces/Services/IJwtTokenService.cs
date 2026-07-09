using FreelanceApp.Domain.Entities;

namespace FreelanceApp.Application.Interfaces.Services;

public interface IJwtTokenService
{
    string GenerateAccessToken(User user);
}