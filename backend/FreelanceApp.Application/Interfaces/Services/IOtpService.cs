using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Interfaces.Services;

public interface IOtpService
{
    Task GenerateAndSendAsync(
        Guid userId,
        string userEmail,
        string userName,
        OtpPurpose purpose,
        CancellationToken ct = default);
}