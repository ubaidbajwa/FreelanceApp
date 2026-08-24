using FluentValidation;
using FreelanceApp.Application.Features.Messaging.DTOs;

namespace FreelanceApp.Application.Features.Messaging.Validators;

public class EditMessageRequestValidator : AbstractValidator<EditMessageRequestDto>
{
    public EditMessageRequestValidator()
    {
        // Same shape as sending — an edit produces a body under the same constraints.
        RuleFor(x => x.Body)
            .NotEmpty().WithMessage("Message body is required")
            .MaximumLength(4000).WithMessage("Message is too long (max 4000)");
    }
}
