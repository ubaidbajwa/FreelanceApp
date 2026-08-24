using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Connections.DTOs;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/connections")]
[Authorize]
public class ConnectionsController(IConnectionService connectionService) : ControllerBase
{
    // ===== REQUESTS =====

    [HttpPost("requests")]
    public async Task<IActionResult> SendRequest(
        [FromBody] SendConnectionRequestDto dto, CancellationToken ct)
    {
        var request = await connectionService.SendRequestAsync(GetUserId(), dto.ReceiverId, ct);
        return Ok(request);
    }

    [HttpPost("requests/{id:guid}/accept")]
    public async Task<IActionResult> AcceptRequest(Guid id, CancellationToken ct)
    {
        await connectionService.AcceptRequestAsync(GetUserId(), id, ct);
        return NoContent();
    }

    [HttpPost("requests/{id:guid}/reject")]
    public async Task<IActionResult> RejectRequest(Guid id, CancellationToken ct)
    {
        await connectionService.RejectRequestAsync(GetUserId(), id, ct);
        return NoContent();
    }

    [HttpDelete("requests/{id:guid}")]
    public async Task<IActionResult> WithdrawRequest(Guid id, CancellationToken ct)
    {
        await connectionService.WithdrawRequestAsync(GetUserId(), id, ct);
        return NoContent();
    }

    // ===== LISTS =====

    [HttpGet]
    public async Task<IActionResult> GetMyConnections(CancellationToken ct)
    {
        var connections = await connectionService.GetMyConnectionsAsync(GetUserId(), ct);
        return Ok(connections);
    }

    [HttpGet("requests/incoming")]
    public async Task<IActionResult> GetIncomingRequests(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var requests = await connectionService.GetIncomingRequestsAsync(GetUserId(), page, pageSize, ct);
        return Ok(requests);
    }

    [HttpGet("requests/outgoing")]
    public async Task<IActionResult> GetOutgoingRequests(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var requests = await connectionService.GetOutgoingRequestsAsync(GetUserId(), page, pageSize, ct);
        return Ok(requests);
    }

    // ===== STATUS =====

    [HttpGet("status/{otherUserId:guid}")]
    public async Task<IActionResult> GetStatusWith(Guid otherUserId, CancellationToken ct)
    {
        var status = await connectionService.GetStatusWithAsync(GetUserId(), otherUserId, ct);
        return Ok(status);
    }

    // ===== HELPERS =====

    private Guid GetUserId()
    {
        var userIdClaim = User.FindFirst("sub")?.Value
                       ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            throw new UnauthorizedException("Invalid user token");

        return userId;
    }
}
