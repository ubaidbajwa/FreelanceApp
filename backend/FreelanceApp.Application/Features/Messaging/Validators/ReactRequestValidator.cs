using FluentValidation;
using FreelanceApp.Application.Features.Messaging.DTOs;

namespace FreelanceApp.Application.Features.Messaging.Validators;

public class ReactRequestValidator : AbstractValidator<ReactRequestDto>
{
    public ReactRequestValidator()
    {
        RuleFor(x => x.Emoji)
            .NotEmpty().WithMessage("Emoji is required")
            // Matches the column width — room for a multi-codepoint emoji (ZWJ + skin tone).
            .MaximumLength(16).WithMessage("Emoji is too long (max 16)");
    }
}
