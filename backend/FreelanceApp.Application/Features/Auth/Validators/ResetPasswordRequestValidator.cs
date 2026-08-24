using FluentValidation;
using FreelanceApp.Application.Features.Auth.DTOs;

namespace FreelanceApp.Application.Features.Auth.Validators;

public class ResetPasswordRequestValidator : AbstractValidator<ResetPasswordRequestDto>
{
    public ResetPasswordRequestValidator()
    {
        RuleFor(x => x.Email)
            .NotEmpty().WithMessage("Email is required")
            .EmailAddress().WithMessage("Email format is invalid");

        RuleFor(x => x.Otp)
            .NotEmpty().WithMessage("OTP is required")
            .Matches(@"^\d{6}$").WithMessage("OTP must be exactly 6 digits");

        RuleFor(x => x.NewPassword)
            .StrongPassword();
    }
}
