using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Exceptions;
using FreelanceApp.Application.Features.Auth.DTOs;
using FreelanceApp.Application.Features.Auth.Services;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Xunit;

namespace FreelanceApp.Tests.Auth;

public class RegisterCaptchaTests
{
    // Captcha runs before any DB work, so only the verifier and (recording) user
    // repo need real behaviour — the rest are throwing stubs that must NOT be hit.
    private static AuthService BuildSut(bool captchaResult, RecordingUserRepository userRepo) =>
        new(
            userRepo,
            new ThrowingPasswordHasher(),
            new ThrowingJwtTokenService(),
            new ThrowingRefreshTokenService(),
            Options.Create(new JwtSettings()),
            new ThrowingOtpService(),
            new ThrowingEmailOtpRepository(),
            new ThrowingProfileRepository(),
            new StubCaptchaVerifier(captchaResult),
            new ThrowingGoogleTokenVerifier(),
            NullLogger<AuthService>.Instance);

    private static RegisterRequestDto ValidDto() => new()
    {
        Email = "new@example.com",
        Password = "Sup3r$ecret!",
        FullName = "New User",
        Role = UserRole.Freelancer,
        CaptchaToken = "some-token"
    };

    [Fact]
    public async Task RegisterAsync_Throws_WhenCaptchaFails()
    {
        var userRepo = new RecordingUserRepository();
        var sut = BuildSut(captchaResult: false, userRepo);

        var ex = await Assert.ThrowsAsync<ValidationException>(() => sut.RegisterAsync(ValidDto()));

        Assert.Equal(400, ex.StatusCode);
        Assert.Equal("Captcha verification failed", ex.Message);
    }

    [Fact]
    public async Task RegisterAsync_CreatesNoUser_WhenCaptchaFails()
    {
        var userRepo = new RecordingUserRepository();
        var sut = BuildSut(captchaResult: false, userRepo);

        await Assert.ThrowsAsync<ValidationException>(() => sut.RegisterAsync(ValidDto()));

        // Fail before touching the DB: no existence probe, no insert.
        Assert.False(userRepo.EmailExistsCalled);
        Assert.False(userRepo.AddCalled);
    }

    // ===== Test doubles =====

    private sealed class StubCaptchaVerifier(bool result) : ICaptchaVerifier
    {
        public Task<bool> VerifyAsync(string token, CancellationToken ct) => Task.FromResult(result);
    }

    private sealed class RecordingUserRepository : IUserRepository
    {
        public bool EmailExistsCalled { get; private set; }
        public bool AddCalled { get; private set; }

        public Task<bool> EmailExistsAsync(string email)
        {
            EmailExistsCalled = true;
            return Task.FromResult(false);
        }

        public Task AddAsync(User user)
        {
            AddCalled = true;
            return Task.CompletedTask;
        }

        public Task SaveChangesAsync() => Task.CompletedTask;
        public Task<User?> GetByIdAsync(Guid id) => Task.FromResult<User?>(null);
        public Task<User?> GetByEmailAsync(string email) => Task.FromResult<User?>(null);
        public Task<User?> GetByExternalIdAsync(AuthProvider provider, string externalId) => Task.FromResult<User?>(null);
        public Task<Guid?> GetSecurityStampAsync(Guid userId) => Task.FromResult<Guid?>(null);
    }

    private sealed class ThrowingGoogleTokenVerifier : IGoogleTokenVerifier
    {
        public Task<GoogleUserPayload?> VerifyAsync(string idToken, CancellationToken ct)
            => throw new InvalidOperationException("should not be called");
    }

    private sealed class ThrowingPasswordHasher : IPasswordHasher
    {
        public string HashPassword(string plainPassword) => throw new InvalidOperationException("should not be called");
        public bool VerifyPassword(string plainPassword, string hashedPassword) => throw new InvalidOperationException("should not be called");
        public bool NeedsRehash(string hashedPassword) => throw new InvalidOperationException("should not be called");
    }

    private sealed class ThrowingJwtTokenService : IJwtTokenService
    {
        public string GenerateAccessToken(User user) => throw new InvalidOperationException("should not be called");
    }

    private sealed class ThrowingRefreshTokenService : IRefreshTokenService
    {
        public Task<string> GenerateAsync(Guid userId, Guid securityStamp) => throw new InvalidOperationException("should not be called");
        public Task<RefreshTokenPayload?> ValidateAndConsumeAsync(string refreshToken) => throw new InvalidOperationException("should not be called");
        public Task RevokeAsync(string refreshToken) => throw new InvalidOperationException("should not be called");
        public Task RevokeAllForUserAsync(Guid userId) => throw new InvalidOperationException("should not be called");
    }

    private sealed class ThrowingOtpService : IOtpService
    {
        public Task GenerateAndSendAsync(Guid userId, string userEmail, string userName, OtpPurpose purpose, CancellationToken ct = default)
            => throw new InvalidOperationException("should not be called");
    }

    private sealed class ThrowingEmailOtpRepository : IEmailOtpRepository
    {
        public Task<EmailOtp?> GetLatestActiveOtpAsync(Guid userId, OtpPurpose purpose) => throw new InvalidOperationException("should not be called");
        public Task<EmailOtp?> GetLatestOtpAsync(Guid userId, OtpPurpose purpose) => throw new InvalidOperationException("should not be called");
    }

    private sealed class ThrowingProfileRepository : IProfileRepository
    {
        public Task<Profile?> GetByUserIdAsync(Guid userId) => throw new InvalidOperationException("should not be called");
        public Task<bool> UsernameExistsAsync(string username, Guid? excludeUserId = null) => throw new InvalidOperationException("should not be called");
        public Task AddAsync(Profile profile) => throw new InvalidOperationException("should not be called");
        public Task<Experience?> GetExperienceByIdAsync(Guid id) => throw new InvalidOperationException("should not be called");
        public Task AddExperienceAsync(Experience experience) => throw new InvalidOperationException("should not be called");
        public void RemoveExperience(Experience experience) => throw new InvalidOperationException("should not be called");
        public Task SaveChangesAsync() => throw new InvalidOperationException("should not be called");
    }
}
