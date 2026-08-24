using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/network")]
[Authorize]
public class NetworkController(
    INetworkService networkService,
    ISuggestionService suggestionService,
    IFollowService followService) : ControllerBase
{
    [HttpGet("overview")]
    [ProducesResponseType(typeof(NetworkOverviewResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetOverview(CancellationToken ct)
    {
        var overview = await networkService.GetOverviewAsync(GetUserId(), ct);
        return Ok(overview);
    }

    [HttpGet("suggestions")]
    [ProducesResponseType(typeof(PagedResult<SuggestionResponse>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetSuggestions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        CancellationToken ct = default)
    {
        var result = await suggestionService.GetSuggestionsAsync(GetUserId(), page, pageSize, ct);
        return Ok(result);
    }

    [HttpPost("suggestions/{userId:guid}/dismiss")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> DismissSuggestion(Guid userId, CancellationToken ct)
    {
        await suggestionService.DismissAsync(GetUserId(), userId, ct);
        return NoContent();
    }

    [HttpDelete("suggestions/{userId:guid}/dismiss")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> UndismissSuggestion(Guid userId, CancellationToken ct)
    {
        await suggestionService.UndismissAsync(GetUserId(), userId, ct);
        return NoContent();
    }

    // ===== Follow endpoints =====

    [HttpPost("follow/{userId:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Follow(Guid userId, CancellationToken ct)
    {
        await followService.FollowAsync(GetUserId(), userId, ct);
        return NoContent();
    }

    [HttpDelete("follow/{userId:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Unfollow(Guid userId, CancellationToken ct)
    {
        await followService.UnfollowAsync(GetUserId(), userId, ct);
        return NoContent();
    }

    [HttpGet("followers")]
    [ProducesResponseType(typeof(PagedResult<FollowUserResponse>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetFollowers(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var result = await followService.GetFollowersAsync(GetUserId(), page, pageSize, ct);
        return Ok(result);
    }

    [HttpGet("following")]
    [ProducesResponseType(typeof(PagedResult<FollowUserResponse>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetFollowing(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var result = await followService.GetFollowingAsync(GetUserId(), page, pageSize, ct);
        return Ok(result);
    }

    [HttpGet("follow/{userId:guid}/status")]
    [ProducesResponseType(typeof(FollowStatusResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetFollowStatus(Guid userId, CancellationToken ct)
    {
        var result = await followService.GetFollowStatusAsync(GetUserId(), userId, ct);
        return Ok(result);
    }

    [HttpGet("follow-suggestions")]
    [ProducesResponseType(typeof(PagedResult<FollowSuggestionResponse>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetFollowSuggestions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 10,
        CancellationToken ct = default)
    {
        var result = await followService.GetFollowSuggestionsAsync(GetUserId(), page, pageSize, ct);
        return Ok(result);
    }

    [HttpPost("follow-suggestions/{userId:guid}/dismiss")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> DismissFollowSuggestion(Guid userId, CancellationToken ct)
    {
        await followService.DismissFollowSuggestionAsync(GetUserId(), userId, ct);
        return NoContent();
    }

    [HttpDelete("follow-suggestions/{userId:guid}/dismiss")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> UndismissFollowSuggestion(Guid userId, CancellationToken ct)
    {
        await followService.UndismissFollowSuggestionAsync(GetUserId(), userId, ct);
        return NoContent();
    }

    private Guid GetUserId()
    {
        var userIdClaim = User.FindFirst("sub")?.Value
                       ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            throw new UnauthorizedException("Invalid user token");

        return userId;
    }
}
