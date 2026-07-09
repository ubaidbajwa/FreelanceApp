using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;

namespace FreelanceApp.Infrastructure.Services;

public class JwtTokenService(IOptions<JwtSettings> jwtOptions) : IJwtTokenService
{
    private readonly JwtSettings _settings = jwtOptions.Value;

    public string GenerateAccessToken(User user)
    {
        // Step 1: Claims define karo
        var claims = new List<Claim>
        {
            // Standard claims (RFC 7519)
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(JwtRegisteredClaimNames.Email, user.Email),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new(JwtRegisteredClaimNames.Iat,
                DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(),
                ClaimValueTypes.Integer64),

             new Claim("security_stamp", user.SecurityStamp.ToString()), 

            // Custom claims (humare app ke liye unique)
            new("role", user.Role.ToString()),
            new("full_name", user.FullName),
            new("identity_verified", user.IsIdentityVerified.ToString().ToLower())
        };

        // Step 2: Signing key prepare karo
        var key = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(_settings.Secret));

        var credentials = new SigningCredentials(
            key,
            SecurityAlgorithms.HmacSha256);

        // Step 3: Token banao
        var token = new JwtSecurityToken(
            issuer: _settings.Issuer,
            audience: _settings.Audience,
            claims: claims,
            notBefore: DateTime.UtcNow,
            expires: DateTime.UtcNow.AddMinutes(_settings.AccessTokenExpiryMinutes),
            signingCredentials: credentials);

        // Step 4: String mein convert karo
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}