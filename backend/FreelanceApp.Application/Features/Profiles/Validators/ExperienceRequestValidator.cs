using FluentValidation;
using FreelanceApp.Application.Features.Profiles.DTOs;

namespace FreelanceApp.Application.Features.Profiles.Validators;

public class ExperienceRequestValidator : AbstractValidator<ExperienceRequestDto>
{
    public ExperienceRequestValidator()
    {
        RuleFor(x => x.Title)
            .NotEmpty().WithMessage("Title is required")
            .MaximumLength(100).WithMessage("Title is too long (max 100)");

        RuleFor(x => x.Company)
            .NotEmpty().WithMessage("Company is required")
            .MaximumLength(100).WithMessage("Company is too long (max 100)");

        RuleFor(x => x.StartDate)
            .NotEmpty().WithMessage("Start date is required")
            .Must(d => d <= DateOnly.FromDateTime(DateTime.UtcNow))
            .WithMessage("Start date cannot be in the future");

        RuleFor(x => x.EndDate)
            .Must((dto, endDate) => dto.StartDate <= endDate!.Value)
            .WithMessage("End date must be on or after start date")
            .Must(endDate => endDate!.Value <= DateOnly.FromDateTime(DateTime.UtcNow))
            .WithMessage("End date cannot be in the future")
            .When(x => x.EndDate != null);

        RuleFor(x => x.Description)
            .MaximumLength(1000).WithMessage("Description is too long (max 1000)")
            .When(x => x.Description != null);
    }
}
