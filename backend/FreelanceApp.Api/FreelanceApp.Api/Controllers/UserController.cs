using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.People.DTOs;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/users")]
[Authorize]   // Default: all endpoints require auth
public class UserController(ICurrentUserService currentUser, IPeopleService peopleService) : ControllerBase
{
    // People directory — search other users to connect with. Each row carries the
    // connection status vs the current user so the frontend needs no extra call.
    [HttpGet]
    public async Task<IActionResult> Search([FromQuery] PeopleQuery query, CancellationToken ct)
    {
        var userId = currentUser.UserId
            ?? throw new UnauthorizedException("Invalid user token");

        var result = await peopleService.SearchAsync(userId, query, ct);
        return Ok(result);
    }

    [HttpGet("me")]
    public IActionResult GetMe()
    {
        return Ok(new
        {
            userId = currentUser.UserId,
            email = currentUser.Email,
            role = currentUser.Role,
            isIdentityVerified = currentUser.IsIdentityVerified,
            isAuthenticated = currentUser.IsAuthenticated
        });
    }

    [HttpGet("me/freelancer-area")]
    [Authorize(Policy = "FreelancerOnly")]
    public IActionResult FreelancerArea()
    {
        return Ok(new
        {
            message = "Welcome Freelancer! Yeh area sirf Freelancers ke liye hai.",
            yourId = currentUser.UserId
        });
    }

    [HttpGet("me/withdraw-eligibility")]
    [Authorize(Policy = "IdentityVerified")]
    public IActionResult WithdrawEligibility()
    {
        return Ok(new
        {
            eligible = true,
            message = "Identity verified! Aap withdrawal kar sakte hain."
        });
    }
}