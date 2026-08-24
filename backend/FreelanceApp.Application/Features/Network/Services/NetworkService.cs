using FreelanceApp.Application.Features.Network.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;

namespace FreelanceApp.Application.Features.Network.Services;

public sealed class NetworkService(
    IConnectionRepository connectionRepository,
    IFollowRepository followRepository) : INetworkService
{
    public async Task<NetworkOverviewResponse> GetOverviewAsync(Guid userId, CancellationToken ct = default)
    {
        var (connections, invitesSent, invitesReceived) =
            await connectionRepository.GetCountsAsync(userId, ct);

        var (following, followers) =
            await followRepository.GetFollowCountsAsync(userId, ct);

        return new NetworkOverviewResponse(connections, invitesSent, invitesReceived, following, followers);
    }
}
