using Microsoft.AspNetCore.SignalR;
using System.IdentityModel.Tokens.Jwt;

namespace FreelanceApp.Api.Services;

/// <summary>
/// Maps a SignalR connection to the authenticated user's id so the notifier can target
/// Clients.User(id) / Clients.Users(ids) and reach EVERY device that user is signed in on.
///
/// Returns the "sub" claim — exactly what JwtTokenService emits (user.Id.ToString()). The
/// JWT pipeline runs with MapInboundClaims = false, so the claim stays "sub" (not remapped
/// to ClaimTypes.NameIdentifier). This deliberately avoids a hand-rolled connectionId
/// dictionary, which breaks on multi-device and is lost on server restart.
/// </summary>
public class ChatUserIdProvider : IUserIdProvider
{
    public string? GetUserId(HubConnectionContext connection) =>
        connection.User?.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
}
