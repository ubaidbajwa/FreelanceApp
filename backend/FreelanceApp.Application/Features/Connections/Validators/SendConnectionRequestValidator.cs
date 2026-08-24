using FluentValidation;
using FreelanceApp.Application.Features.Connections.DTOs;

namespace FreelanceApp.Application.Features.Connections.Validators;

public class SendConnectionRequestValidator : AbstractValidator<SendConnectionRequestDto>
{
    public SendConnectionRequestValidator()
    {
        // Auto-validation sync hoti hai, is liye "user really exists" ka DB check
        // service mein hai (404 NotFound) — yahan sirf shape validate hota hai.
        RuleFor(x => x.ReceiverId)
            .NotEmpty().WithMessage("ReceiverId is required");
    }
}
