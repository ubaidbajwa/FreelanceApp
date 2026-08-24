using FluentValidation;
using FreelanceApp.Application.Features.Profiles.DTOs;

namespace FreelanceApp.Application.Features.Profiles.Validators;

public class UpdateProfileRequestValidator : AbstractValidator<UpdateProfileRequestDto>
{
    public UpdateProfileRequestValidator()
    {
        // Partial update — rules sirf tab chalein jab field bheji gayi ho (non-null)

        RuleFor(x => x.DisplayName)
            .NotEmpty().WithMessage("Display name cannot be empty")
            .MaximumLength(100).WithMessage("Display name is too long (max 100)")
            .When(x => x.DisplayName != null);

        RuleFor(x => x.Headline)
            .MaximumLength(150).WithMessage("Headline is too long (max 150)")
            .When(x => x.Headline != null);

        RuleFor(x => x.Bio)
            .MaximumLength(2000).WithMessage("Bio is too long (max 2000)")
            .When(x => x.Bio != null);

        RuleFor(x => x.HourlyRate)
            .GreaterThan(0).WithMessage("Hourly rate must be greater than 0")
            .LessThanOrEqualTo(10000).WithMessage("Hourly rate is unrealistically high")
            .When(x => x.HourlyRate != null);

        RuleFor(x => x.Availability)
            .IsInEnum().WithMessage("Invalid availability value")
            .When(x => x.Availability != null);

        RuleFor(x => x.WorkPreference)
            .IsInEnum().WithMessage("Invalid work preference value")
            .When(x => x.WorkPreference != null);

        RuleFor(x => x.AvailabilityStatus)
            .IsInEnum().WithMessage("Invalid availability status value")
            .When(x => x.AvailabilityStatus != null);

        RuleFor(x => x.ClientType)
            .IsInEnum().WithMessage("Invalid client type value")
            .When(x => x.ClientType != null);

        // LENIENT: BusinessName-when-Business ko backend hard-require NAHI karta —
        // partial update + progressive profiling ke liye. Wo UX gate frontend enforce
        // karega; yahan sirf shape (length) validate hoti hai.
        RuleFor(x => x.BusinessName)
            .MaximumLength(100).WithMessage("Business name is too long (max 100)")
            .When(x => x.BusinessName != null);

        RuleFor(x => x.Country)
            .MaximumLength(100).WithMessage("Country is too long (max 100)")
            .When(x => x.Country != null);

        RuleFor(x => x.City)
            .MaximumLength(100).WithMessage("City is too long (max 100)")
            .When(x => x.City != null);

        RuleFor(x => x.Skills)
            .Must(s => s!.Count <= 30).WithMessage("Maximum 30 skills allowed")
            .When(x => x.Skills != null);

        RuleForEach(x => x.Skills)
            .NotEmpty().WithMessage("Skill cannot be empty")
            .MaximumLength(50).WithMessage("Skill is too long (max 50)")
            .When(x => x.Skills != null);

        RuleFor(x => x.DesiredJobTitles)
            .Must(s => s!.Count <= 5).WithMessage("Maximum 5 desired job titles allowed")
            .When(x => x.DesiredJobTitles != null);

        RuleForEach(x => x.DesiredJobTitles)
            .NotEmpty().WithMessage("Job title cannot be empty")
            .MaximumLength(100).WithMessage("Job title is too long (max 100)")
            .When(x => x.DesiredJobTitles != null);

        RuleFor(x => x.DesiredJobLocations)
            .Must(s => s!.Count <= 5).WithMessage("Maximum 5 desired job locations allowed")
            .When(x => x.DesiredJobLocations != null);

        RuleForEach(x => x.DesiredJobLocations)
            .NotEmpty().WithMessage("Job location cannot be empty")
            .MaximumLength(100).WithMessage("Job location is too long (max 100)")
            .When(x => x.DesiredJobLocations != null);

        RuleFor(x => x.HiringInterests)
            .Must(s => s!.Count <= 5).WithMessage("Maximum 5 hiring interests allowed")
            .When(x => x.HiringInterests != null);

        RuleForEach(x => x.HiringInterests)
            .NotEmpty().WithMessage("Hiring interest cannot be empty")
            .MaximumLength(100).WithMessage("Hiring interest is too long (max 100)")
            .When(x => x.HiringInterests != null);

        RuleFor(x => x.HiringType)
            .IsInEnum().WithMessage("Invalid hiring type value")
            .When(x => x.HiringType != null);
    }
}
