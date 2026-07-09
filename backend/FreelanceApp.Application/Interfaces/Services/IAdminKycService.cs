using FreelanceApp.Application.Features.Kyc.DTOs;

namespace FreelanceApp.Application.Interfaces.Services;

public interface IAdminKycService
{
    Task<List<AdminKycCaseDto>> GetPendingCasesAsync();
    Task ApproveAsync(Guid verificationId);
    Task RejectAsync(Guid verificationId, string reason);
}
