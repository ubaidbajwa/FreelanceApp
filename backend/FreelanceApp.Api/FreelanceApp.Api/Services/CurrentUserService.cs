using FreelanceApp.Application.Interfaces.Services;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;

namespace FreelanceApp.Api.Services;

public class CurrentUserService(IHttpContextAccessor httpContextAccessor)
    : ICurrentUserService
{
    private ClaimsPrincipal? User =>
        httpContextAccessor.HttpContext?.User;

    public Guid? UserId
    {
        get
        {
            var sub = User?.FindFirstValue(JwtRegisteredClaimNames.Sub);
            return Guid.TryParse(sub, out var id) ? id : null;
        }
    }

    public string? Email =>
        User?.FindFirstValue(JwtRegisteredClaimNames.Email);

    public string? Role =>
        User?.FindFirstValue("role");

    public bool IsIdentityVerified
    {
        get
        {
            var claim = User?.FindFirstValue("identity_verified");
            return bool.TryParse(claim, out var verified) && verified;
        }
    }

    public bool IsAuthenticated =>
        User?.Identity?.IsAuthenticated ?? false;
}