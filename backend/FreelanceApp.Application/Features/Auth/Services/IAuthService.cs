using FreelanceApp.Application.Features.Auth.DTOs;

namespace FreelanceApp.Application.Features.Auth.Services;

public interface IAuthService
{
    Task RegisterAsync(RegisterRequestDto dto);
    Task<bool> EmailExistsAsync(string email);
    Task<AuthResponseDto> LoginAsync(LoginRequestDto dto);
    Task<AuthResponseDto> GoogleLoginAsync(GoogleLoginRequest request, CancellationToken ct = default);
    Task<AuthResponseDto> RefreshAsync(RefreshTokenRequestDto dto);
    Task LogoutAsync(LogoutRequestDto dto);
    Task VerifyEmailAsync(VerifyEmailRequestDto dto);
    Task ResendOtpAsync(ResendOtpRequestDto dto);
    Task ForgotPasswordAsync(ForgotPasswordRequestDto dto);

    Task ResetPasswordAsync(ResetPasswordRequestDto dto);

    Task<AuthResponseDto> ChangePasswordAsync(Guid userId, ChangePasswordRequestDto dto);
}