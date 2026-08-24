using FluentValidation;
using FreelanceApp.Application.Features.Auth.DTOs;

namespace FreelanceApp.Application.Features.Auth.Validators;

/// <summary>
/// Sirf NewPassword pe strong policy — CurrentPassword ki validation
/// DTO ke [Required] attribute se hi hoti hai (usko change nahi karna,
/// warna purane weak passwords wale users apna password change hi nahi kar payenge).
/// </summary>
public class ChangePasswordRequestValidator : AbstractValidator<ChangePasswordRequestDto>
{
    public ChangePasswordRequestValidator()
    {
        RuleFor(x => x.NewPassword)
            .StrongPassword();
    }
}
