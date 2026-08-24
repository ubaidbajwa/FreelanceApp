using FluentValidation;
using FreelanceApp.Application.Features.Messaging.DTOs;

namespace FreelanceApp.Application.Features.Messaging.Validators;

public class ForwardMessagesRequestValidator : AbstractValidator<ForwardMessagesRequestDto>
{
    // Cap the batch so one call can't fan out an unbounded write. 20 comfortably covers a
    // multi-select; the server still re-checks every id and participant gate per message.
    public const int MaxBatch = 20;

    public ForwardMessagesRequestValidator()
    {
        RuleFor(x => x.TargetConversationId)
            .NotEmpty().WithMessage("Target conversation is required");

        RuleFor(x => x.MessageIds)
            .NotEmpty().WithMessage("At least one message is required")
            .Must(ids => ids.Count <= MaxBatch)
                .WithMessage($"Too many messages (max {MaxBatch})");

        RuleForEach(x => x.MessageIds)
            .NotEmpty().WithMessage("Message id cannot be empty");
    }
}
