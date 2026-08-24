using FluentValidation;
using FreelanceApp.Application.Features.Messaging.DTOs;

namespace FreelanceApp.Application.Features.Messaging.Validators;

public class StartConversationRequestValidator : AbstractValidator<StartConversationRequestDto>
{
    public StartConversationRequestValidator()
    {
        // Shape-only check — "recipient really exists" is a service-layer DB check (404).
        RuleFor(x => x.RecipientId)
            .NotEmpty().WithMessage("RecipientId is required");
    }
}
