using FluentValidation;
using FreelanceApp.Application.Features.Auth.DTOs;

namespace FreelanceApp.Application.Features.Auth.Validators;

public class GoogleLoginRequestValidator : AbstractValidator<GoogleLoginRequest>
{
    public GoogleLoginRequestValidator()
    {
        RuleFor(x => x.IdToken)
            .NotEmpty().WithMessage("Google ID token is required");
    }
}
