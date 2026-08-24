using FreelanceApp.Application.Features.Network.DTOs;

namespace FreelanceApp.Application.Interfaces.Services;

public interface INetworkService
{
    Task<NetworkOverviewResponse> GetOverviewAsync(Guid userId, CancellationToken ct = default);
}
