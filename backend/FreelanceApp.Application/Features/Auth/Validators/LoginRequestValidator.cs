using FluentValidation;
using FreelanceApp.Application.Features.Auth.DTOs;

namespace FreelanceApp.Application.Features.Auth.Validators;

public class LoginRequestValidator : AbstractValidator<LoginRequestDto>
{
    public LoginRequestValidator()
    {
        RuleFor(x => x.Email)
            .NotEmpty().WithMessage("Email is required")
            .EmailAddress().WithMessage("Email format is invalid");

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("Password is required");
    }
}