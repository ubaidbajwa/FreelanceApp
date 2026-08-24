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

public class GoogleLoginTests
{
    private static AuthService BuildSut(FakeUserRepository userRepo, GoogleUserPayload? verifierResult) =>
        new(
            userRepo,
            new StubPasswordHasher(),
            new StubJwtTokenService(),
            new StubRefreshTokenService(),
            Options.Create(new JwtSettings()),
            new ThrowingOtpService(),
            new ThrowingEmailOtpRepository(),
            new StubProfileRepository(),
            new ThrowingCaptchaVerifier(),
            new StubGoogleTokenVerifier(verifierResult),
            NullLogger<AuthService>.Instance);

    private static GoogleUserPayload ValidPayload(string subject = "google-sub-123", string email = "guser@example.com") =>
        new(Subject: subject, Email: email, EmailVerified: true, FullName: "Google User");

    [Fact]
    public async Task GoogleLoginAsync_ThrowsUnauthorized_WhenTokenInvalid()
    {
        var userRepo = new FakeUserRepository();
        // Verifier fails closed → null. This must map to a 401, not a 500.
        var sut = BuildSut(userRepo, verifierResult: null);

        var ex = await Assert.ThrowsAsync<UnauthorizedException>(
            () => sut.GoogleLoginAsync(new GoogleLoginRequest { IdToken = "garbage" }, CancellationToken.None));

        Assert.Equal(401, ex.StatusCode);
        Assert.False(userRepo.AddCalled); // no account created for a bad token
    }

    [Fact]
    public async Task GoogleLoginAsync_ThrowsUnauthorized_WhenGoogleEmailNotVerified()
    {
        var userRepo = new FakeUserRepository();
        var payload = new GoogleUserPayload("sub-x", "unverified@example.com", EmailVerified: false, "X");
        var sut = BuildSut(userRepo, payload);

        var ex = await Assert.ThrowsAsync<UnauthorizedException>(
            () => sut.GoogleLoginAsync(new GoogleLoginRequest { IdToken = "tok" }, CancellationToken.None));

        Assert.Equal(401, ex.StatusCode);
        Assert.False(userRepo.AddCalled);
    }

    [Fact]
    public async Task GoogleLoginAsync_LinksExistingEmail_WithoutCreatingDuplicate()
    {
        var existing = new User
        {
            Id = Guid.NewGuid(),
            Email = "guser@example.com",
            PasswordHash = "existing-hash", // local account with a password
            FullName = "Existing User",
            Provider = AuthProvider.Local,
            ExternalId = null,
            IsEmailVerified = true,
            SecurityStamp = Guid.NewGuid()
        };
        var userRepo = new FakeUserRepository { UserByEmail = existing };
        var sut = BuildSut(userRepo, ValidPayload(subject: "google-sub-999", email: "guser@example.com"));

        var result = await sut.GoogleLoginAsync(new GoogleLoginRequest { IdToken = "tok" }, CancellationToken.None);

        Assert.False(userRepo.AddCalled);                       // no duplicate user
        Assert.True(userRepo.SaveChangesCalled);                // link persisted
        Assert.Equal(AuthProvider.Google, existing.Provider);   // identity linked
        Assert.Equal("google-sub-999", existing.ExternalId);
        Assert.Equal("existing-hash", existing.PasswordHash);   // password preserved
        Assert.Equal(existing.Id, result.User.Id);
    }

    [Fact]
    public async Task GoogleLoginAsync_CreatesNewUser_WithNullPassword()
    {
        var userRepo = new FakeUserRepository(); // no match by external id or email
        var sut = BuildSut(userRepo, ValidPayload(subject: "google-sub-new", email: "brand.new@example.com"));

        var result = await sut.GoogleLoginAsync(new GoogleLoginRequest { IdToken = "tok" }, CancellationToken.None);

        Assert.True(userRepo.AddCalled);
        Assert.NotNull(userRepo.AddedUser);
        Assert.Null(userRepo.AddedUser!.PasswordHash);                     // social-only account
        Assert.Equal(AuthProvider.Google, userRepo.AddedUser.Provider);
        Assert.Equal("google-sub-new", userRepo.AddedUser.ExternalId);
        Assert.Equal("brand.new@example.com", userRepo.AddedUser.Email);
        Assert.True(userRepo.AddedUser.IsEmailVerified);                   // trusted from Google
        Assert.Equal(userRepo.AddedUser.Id, result.User.Id);
    }

    // ===== Test doubles =====

    private sealed class FakeUserRepository : IUserRepository
    {
        public User? UserByExternalId { get; set; }
        public User? UserByEmail { get; set; }
        public bool AddCalled { get; private set; }
        public bool SaveChangesCalled { get; private set; }
        public User? AddedUser { get; private set; }

        public Task<User?> GetByExternalIdAsync(AuthProvider provider, string externalId)
            => Task.FromResult(UserByExternalId);

        public Task<User?> GetByEmailAsync(string email) => Task.FromResult(UserByEmail);

        public Task AddAsync(User user)
        {
            AddCalled = true;
            AddedUser = user;
            return Task.CompletedTask;
        }

        public Task SaveChangesAsync()
        {
            SaveChangesCalled = true;
            return Task.CompletedTask;
        }

        public Task<bool> EmailExistsAsync(string email) => Task.FromResult(false);
        public Task<User?> GetByIdAsync(Guid id) => Task.FromResult<User?>(null);
        public Task<Guid?> GetSecurityStampAsync(Guid userId) => Task.FromResult<Guid?>(null);
    }

    private sealed class StubGoogleTokenVerifier(GoogleUserPayload? result) : IGoogleTokenVerifier
    {
        public Task<GoogleUserPayload?> VerifyAsync(string idToken, CancellationToken ct) => Task.FromResult(result);
    }

    private sealed class StubJwtTokenService : IJwtTokenService
    {
        public string GenerateAccessToken(User user) => "access-token";
    }

    private sealed class StubRefreshTokenService : IRefreshTokenService
    {
        public Task<string> GenerateAsync(Guid userId, Guid securityStamp) => Task.FromResult("refresh-token");
        public Task<RefreshTokenPayload?> ValidateAndConsumeAsync(string refreshToken) => Task.FromResult<RefreshTokenPayload?>(null);
        public Task RevokeAsync(string refreshToken) => Task.CompletedTask;
        public Task RevokeAllForUserAsync(Guid userId) => Task.CompletedTask;
    }

    private sealed class StubProfileRepository : IProfileRepository
    {
        public Task<Profile?> GetByUserIdAsync(Guid userId) => Task.FromResult<Profile?>(null);
        public Task<bool> UsernameExistsAsync(string username, Guid? excludeUserId = null) => Task.FromResult(false);
        public Task AddAsync(Profile profile) => Task.CompletedTask;
        public Task<Experience?> GetExperienceByIdAsync(Guid id) => Task.FromResult<Experience?>(null);
        public Task AddExperienceAsync(Experience experience) => Task.CompletedTask;
        public void RemoveExperience(Experience experience) { }
        public Task SaveChangesAsync() => Task.CompletedTask;
    }

    private sealed class StubPasswordHasher : IPasswordHasher
    {
        public string HashPassword(string plainPassword) => "hashed";
        public bool VerifyPassword(string plainPassword, string hashedPassword) => true;
        public bool NeedsRehash(string hashedPassword) => false;
    }

    private sealed class ThrowingCaptchaVerifier : ICaptchaVerifier
    {
        public Task<bool> VerifyAsync(string token, CancellationToken ct) => throw new InvalidOperationException("should not be called");
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
}
