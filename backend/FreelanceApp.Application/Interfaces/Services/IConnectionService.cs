using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Connections.DTOs;

namespace FreelanceApp.Application.Interfaces.Services;

public interface IConnectionService
{
    Task<ConnectionRequestResponseDto> SendRequestAsync(Guid userId, Guid receiverId, CancellationToken ct = default);
    Task AcceptRequestAsync(Guid userId, Guid connectionId, CancellationToken ct = default);
    Task RejectRequestAsync(Guid userId, Guid connectionId, CancellationToken ct = default);
    Task WithdrawRequestAsync(Guid userId, Guid connectionId, CancellationToken ct = default);

    Task<List<ConnectionUserDto>> GetMyConnectionsAsync(Guid userId, CancellationToken ct = default);
    Task<PagedResult<PendingRequestDto>> GetIncomingRequestsAsync(Guid userId, int page = 1, int pageSize = 20, CancellationToken ct = default);
    Task<PagedResult<PendingRequestDto>> GetOutgoingRequestsAsync(Guid userId, int page = 1, int pageSize = 20, CancellationToken ct = default);

    Task<ConnectionStatusResponseDto> GetStatusWithAsync(Guid userId, Guid otherUserId, CancellationToken ct = default);
}
