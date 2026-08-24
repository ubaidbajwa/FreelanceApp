using FluentValidation;
using FreelanceApp.Application.Features.Messaging.DTOs;

namespace FreelanceApp.Application.Features.Messaging.Validators;

public class SendMessageRequestValidator : AbstractValidator<SendMessageRequestDto>
{
    public SendMessageRequestValidator()
    {
        RuleFor(x => x.Body)
            .NotEmpty().WithMessage("Message body is required")
            .MaximumLength(4000).WithMessage("Message is too long (max 4000)");
    }
}
