using FluentValidation;
using FreelanceApp.Application.Features.Messaging.DTOs;

namespace FreelanceApp.Application.Features.Messaging.Validators;

public class PinMessageRequestDtoValidator : AbstractValidator<PinMessageRequestDto>
{
    public PinMessageRequestDtoValidator()
    {
        RuleFor(x => x.Duration)
            .IsInEnum()
            .WithMessage("Duration must be a valid PinDuration value (0 = 24 hours, 1 = 7 days, 2 = 30 days).");
    }
}
