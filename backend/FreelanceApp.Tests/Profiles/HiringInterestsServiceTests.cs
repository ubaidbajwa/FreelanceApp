using FreelanceApp.Application.Features.Profiles.DTOs;
using FreelanceApp.Application.Features.Profiles.Services;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using Microsoft.Extensions.Logging.Abstractions;

namespace FreelanceApp.Tests.Profiles;

public class HiringInterestsServiceTests
{
    private static (ProfileService sut, FakeProfileRepository repo) Build(Profile? existing = null)
    {
        var repo = new FakeProfileRepository(existing);
        var sut = new ProfileService(repo, new StubUserRepository(), new StubImageStorage(),
            NullLogger<ProfileService>.Instance);
        return (sut, repo);
    }

    private static Profile ExistingProfile(Guid userId) => new()
    {
        Id = Guid.NewGuid(),
        UserId = userId,
        DisplayName = "Test User",
        CreatedAt = DateTime.UtcNow,
        UpdatedAt = DateTime.UtcNow,
        Experiences = []
    };

    [Fact]
    public async Task HiringInterests_CaseInsensitiveDuplicatesCollapse()
    {
        var userId = Guid.NewGuid();
        var (sut, _) = Build(ExistingProfile(userId));

        var result = await sut.UpdateMyProfileAsync(userId, new UpdateProfileRequestDto
        {
            HiringInterests = ["Design", "design", "DESIGN", "Development"]
        });

        Assert.Equal(2, result.HiringInterests.Count);
        Assert.Contains("Design", result.HiringInterests);
        Assert.Contains("Development", result.HiringInterests);
    }

    [Fact]
    public async Task HiringInterests_WhitespaceEntriesTrimmedAndFiltered()
    {
        var userId = Guid.NewGuid();
        var (sut, _) = Build(ExistingProfile(userId));

        var result = await sut.UpdateMyProfileAsync(userId, new UpdateProfileRequestDto
        {
            HiringInterests = ["  Design  ", "  ", "Writing"]
        });

        Assert.Equal(2, result.HiringInterests.Count);
        Assert.Contains("Design", result.HiringInterests);
        Assert.Contains("Writing", result.HiringInterests);
    }

    [Fact]
    public async Task HiringInterests_Null_LeavesExistingUnchanged()
    {
        var userId = Guid.NewGuid();
        var profile = ExistingProfile(userId);
        profile.HiringInterests = ["SEO"];
        var (sut, _) = Build(profile);

        var result = await sut.UpdateMyProfileAsync(userId, new UpdateProfileRequestDto
        {
            HiringInterests = null
        });

        Assert.Single(result.HiringInterests);
        Assert.Contains("SEO", result.HiringInterests);
    }

    [Fact]
    public async Task HiringType_SetAndReturnedCorrectly()
    {
        var userId = Guid.NewGuid();
        var (sut, _) = Build(ExistingProfile(userId));

        var result = await sut.UpdateMyProfileAsync(userId, new UpdateProfileRequestDto
        {
            HiringType = HiringType.OngoingWork
        });

        Assert.Equal(HiringType.OngoingWork, result.HiringType);
    }

    [Fact]
    public async Task HiringType_Null_LeavesExistingUnchanged()
    {
        var userId = Guid.NewGuid();
        var profile = ExistingProfile(userId);
        profile.HiringType = HiringType.OneTimeProject;
        var (sut, _) = Build(profile);

        var result = await sut.UpdateMyProfileAsync(userId, new UpdateProfileRequestDto
        {
            HiringType = null
        });

        Assert.Equal(HiringType.OneTimeProject, result.HiringType);
    }

    // ===== INVITE POLICY ROUND-TRIP (N7 — profile flow) =====

    [Fact]
    public async Task InvitePolicy_SetViaPut_ReturnedInGet()
    {
        var userId = Guid.NewGuid();
        var (sut, _) = Build(ExistingProfile(userId));

        var updated = await sut.UpdateMyProfileAsync(userId, new UpdateProfileRequestDto
        {
            InvitePolicy = ConnectionInvitePolicy.MutualsOnly
        });

        Assert.Equal(ConnectionInvitePolicy.MutualsOnly, updated.InvitePolicy);

        // GET re-reads from the repo — should return the saved value
        var fetched = await sut.GetMyProfileAsync(userId);
        Assert.Equal(ConnectionInvitePolicy.MutualsOnly, fetched.InvitePolicy);
    }

    [Fact]
    public async Task InvitePolicy_Null_LeavesExistingUnchanged()
    {
        var userId = Guid.NewGuid();
        var profile = ExistingProfile(userId);
        profile.InvitePolicy = ConnectionInvitePolicy.NoOne;
        var (sut, _) = Build(profile);

        var result = await sut.UpdateMyProfileAsync(userId, new UpdateProfileRequestDto
        {
            InvitePolicy = null
        });

        Assert.Equal(ConnectionInvitePolicy.NoOne, result.InvitePolicy);
    }

    [Fact]
    public async Task InvitePolicy_Default_IsNullInResponse()
    {
        var userId = Guid.NewGuid();
        var (sut, _) = Build(ExistingProfile(userId));   // no InvitePolicy set

        var result = await sut.GetMyProfileAsync(userId);

        Assert.Null(result.InvitePolicy);
    }

    // ===== Test doubles =====

    private sealed class FakeProfileRepository(Profile? profile) : IProfileRepository
    {
        private readonly Profile? _profile = profile;

        public Task<Profile?> GetByUserIdAsync(Guid userId) => Task.FromResult(_profile);
        public Task AddAsync(Profile p) => Task.CompletedTask;
        public Task SaveChangesAsync() => Task.CompletedTask;
        public Task<bool> UsernameExistsAsync(string username, Guid? excludeUserId = null) => Task.FromResult(false);
        public Task<Experience?> GetExperienceByIdAsync(Guid id) => Task.FromResult<Experience?>(null);
        public Task AddExperienceAsync(Experience experience) => Task.CompletedTask;
        public void RemoveExperience(Experience experience) { }
    }

    private sealed class StubUserRepository : IUserRepository
    {
        public Task<User?> GetByIdAsync(Guid id) => Task.FromResult<User?>(null);
        public Task<User?> GetByEmailAsync(string email) => Task.FromResult<User?>(null);
        public Task<User?> GetByExternalIdAsync(AuthProvider provider, string externalId) => Task.FromResult<User?>(null);
        public Task<bool> EmailExistsAsync(string email) => Task.FromResult(false);
        public Task AddAsync(User user) => Task.CompletedTask;
        public Task SaveChangesAsync() => Task.CompletedTask;
        public Task<Guid?> GetSecurityStampAsync(Guid userId) => Task.FromResult<Guid?>(null);
    }

    private sealed class StubImageStorage : IImageStorageService
    {
        public Task<string> UploadAsync(Stream stream, string fileName, string folder, CancellationToken ct = default)
            => Task.FromResult("https://example.com/photo.jpg");
        public Task DeleteByUrlAsync(string url, CancellationToken ct = default) => Task.CompletedTask;
    }
}
