using FreelanceApp.Application.Features.Kyc.DTOs;

namespace FreelanceApp.Application.Interfaces.Services;

public interface IKycService
{
    Task<Guid> UploadDocumentsAsync(
        Guid userId,
        KycUploadRequest request,
        CancellationToken ct = default);

    Task<KycStatusResponseDto> GetStatusAsync(Guid userId);
}