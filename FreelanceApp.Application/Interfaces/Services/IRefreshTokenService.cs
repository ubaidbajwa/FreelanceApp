namespace FreelanceApp.Application.Interfaces.Services;

public interface IRefreshTokenService
{
    Task<string> GenerateAsync(Guid userId, Guid securityStamp);
    Task<RefreshTokenPayload?> ValidateAndConsumeAsync(string refreshToken);
    Task RevokeAsync(string refreshToken);
    Task RevokeAllForUserAsync(Guid userId);
}

// SecurityStamp is captured at token creation so a password reset
// (which rotates the stamp) invalidates outstanding refresh tokens too.
public record RefreshTokenPayload(Guid UserId, Guid SecurityStamp);
