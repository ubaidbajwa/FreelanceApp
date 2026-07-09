using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Interfaces.Repositories;

public interface IEmailOtpRepository
{
    Task<EmailOtp?> GetLatestActiveOtpAsync(Guid userId, OtpPurpose purpose);
    Task<EmailOtp?> GetLatestOtpAsync(Guid userId, OtpPurpose purpose);
}