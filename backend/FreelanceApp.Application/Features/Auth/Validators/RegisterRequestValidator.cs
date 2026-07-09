using FluentValidation;
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
            .MaximumLength(255).WithMessage("Email is too long");

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("Password is required")
            .MinimumLength(8).WithMessage("Password must be at least 8 characters")
            .MaximumLength(100).WithMessage("Password is too long")
            .Matches(@"[A-Z]").WithMessage("Password must contain at least one uppercase letter")
            .Matches(@"[a-z]").WithMessage("Password must contain at least one lowercase letter")
            .Matches(@"[0-9]").WithMessage("Password must contain at least one digit");

        RuleFor(x => x.FullName)
            .NotEmpty().WithMessage("Full name is required")
            .MinimumLength(2).WithMessage("Full name is too short")
            .MaximumLength(100).WithMessage("Full name is too long");

        RuleFor(x => x.Role)
            .Must(role => role == UserRole.Freelancer || role == UserRole.Client)
            .WithMessage("Role must be either Freelancer or Client");
    }
}