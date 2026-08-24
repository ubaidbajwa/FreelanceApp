using FluentValidation;

namespace FreelanceApp.Application.Features.Auth.Validators;

/// <summary>
/// Shared strong-password policy — Register, ResetPassword aur ChangePassword
/// (sirf new-password fields) sab isi ek rule ko use karte hain, taake policy
/// ek jagah change ho to har jagah apply ho.
/// </summary>
public static class PasswordRuleExtensions
{
    public static IRuleBuilderOptions<T, string> StrongPassword<T>(
        this IRuleBuilder<T, string> ruleBuilder)
    {
        return ruleBuilder
            .NotEmpty().WithMessage("Password is required")
            .MinimumLength(8).WithMessage("Password must be at least 8 characters")
            .MaximumLength(100).WithMessage("Password is too long")
            .Matches(@"[A-Z]").WithMessage("Password must contain at least one uppercase letter")
            .Matches(@"[a-z]").WithMessage("Password must contain at least one lowercase letter")
            .Matches(@"[0-9]").WithMessage("Password must contain at least one digit")
            .Matches(@"[^a-zA-Z0-9]").WithMessage("Password must contain at least one special character (e.g. ! @ # $ %)");
    }
}
