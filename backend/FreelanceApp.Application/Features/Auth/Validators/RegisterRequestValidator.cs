using FluentValidation;
using FreelanceApp.Application.Common.Security;
using FreelanceApp.Application.Features.Auth.DTOs;
using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Auth.Validators;

public class RegisterRequestValidator : AbstractValidator<RegisterRequestDto>
{
    public RegisterRequestValidator()
    {
        RuleFor(x => x.Email)
            .NotEmpty().WithMessage("Email is required")
            .EmailAddress().WithMessage("Email format is invalid")
            .MaximumLength(255).WithMessage("Email is too long")
            .Must(email => !DisposableEmailDomains.IsDisposable(email))
            .WithMessage("Disposable email addresses are not allowed.");

        RuleFor(x => x.Password)
            .StrongPassword();

        RuleFor(x => x.FullName)
            .NotEmpty().WithMessage("Full name is required")
            .MinimumLength(2).WithMessage("Full name is too short")
            .MaximumLength(100).WithMessage("Full name is too long");

        RuleFor(x => x.Role)
            .Must(role => role == UserRole.Freelancer || role == UserRole.Client)
            .WithMessage("Role must be either Freelancer or Client");

        RuleFor(x => x.CaptchaToken)
            .NotEmpty().WithMessage("Captcha token is required");
    }
}