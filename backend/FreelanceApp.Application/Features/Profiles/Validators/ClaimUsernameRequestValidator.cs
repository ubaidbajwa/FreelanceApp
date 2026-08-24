using FluentValidation;
using FreelanceApp.Application.Features.Profiles.DTOs;

namespace FreelanceApp.Application.Features.Profiles.Validators;

public class ClaimUsernameRequestValidator : AbstractValidator<ClaimUsernameRequestDto>
{
    public ClaimUsernameRequestValidator()
    {
        RuleFor(x => x.Username)
            .NotEmpty().WithMessage("Username is required")
            .Matches(@"^[a-zA-Z][a-zA-Z0-9_]{2,29}$")   // input case-insensitive — service lowercase karta hai
            .WithMessage("Username must be 3-30 characters, letters/digits/underscore only, and start with a letter");
    }
}
