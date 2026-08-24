using FreelanceApp.Application.Features.Profiles.DTOs;
using FreelanceApp.Application.Features.Profiles.Validators;
using FreelanceApp.Domain.Enums;
using Xunit;

namespace FreelanceApp.Tests.Profiles;

public class HiringInterestsValidatorTests
{
    private readonly UpdateProfileRequestValidator _sut = new();

    [Fact]
    public async Task HiringInterests_Null_PassesValidation()
    {
        var result = await _sut.ValidateAsync(new UpdateProfileRequestDto { HiringInterests = null });
        Assert.True(result.IsValid);
    }

    [Fact]
    public async Task HiringInterests_EmptyList_PassesValidation()
    {
        var result = await _sut.ValidateAsync(new UpdateProfileRequestDto { HiringInterests = [] });
        Assert.True(result.IsValid);
    }

    [Fact]
    public async Task HiringInterests_FiveItems_PassesValidation()
    {
        var dto = new UpdateProfileRequestDto
        {
            HiringInterests = ["Design", "Development", "Marketing", "Writing", "SEO"]
        };
        var result = await _sut.ValidateAsync(dto);
        Assert.True(result.IsValid);
    }

    [Fact]
    public async Task HiringInterests_SixItems_FailsValidation()
    {
        var dto = new UpdateProfileRequestDto
        {
            HiringInterests = ["A", "B", "C", "D", "E", "F"]
        };
        var result = await _sut.ValidateAsync(dto);
        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.PropertyName == "HiringInterests" && e.ErrorMessage.Contains("5"));
    }

    [Fact]
    public async Task HiringInterests_EmptyStringEntry_FailsValidation()
    {
        var dto = new UpdateProfileRequestDto { HiringInterests = ["Design", ""] };
        var result = await _sut.ValidateAsync(dto);
        Assert.False(result.IsValid);
    }

    [Fact]
    public async Task HiringType_Null_PassesValidation()
    {
        var result = await _sut.ValidateAsync(new UpdateProfileRequestDto { HiringType = null });
        Assert.True(result.IsValid);
    }

    [Fact]
    public async Task HiringType_ValidEnum_PassesValidation()
    {
        var dto = new UpdateProfileRequestDto { HiringType = HiringType.OneTimeProject };
        var result = await _sut.ValidateAsync(dto);
        Assert.True(result.IsValid);
    }

    [Fact]
    public async Task HiringType_InvalidEnum_FailsValidation()
    {
        var dto = new UpdateProfileRequestDto { HiringType = (HiringType)99 };
        var result = await _sut.ValidateAsync(dto);
        Assert.False(result.IsValid);
        Assert.Contains(result.Errors, e => e.PropertyName == "HiringType");
    }
}
