using FreelanceApp.Application.Common.Capabilities;
using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Profiles.DTOs;

public class ProfileResponseDto
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string DisplayName { get; set; } = string.Empty;
    public string? Headline { get; set; }
    public string? Bio { get; set; }
    public string? ProfilePhotoUrl { get; set; }
    public decimal? HourlyRate { get; set; }
    public Availability? Availability { get; set; }             // JSON mein int (0/1/2) ya null
    public WorkPreference? WorkPreference { get; set; }         // JSON mein int (0/1/2) ya null
    public AvailabilityStatus? AvailabilityStatus { get; set; } // JSON mein int (0/1/2) ya null
    public ClientType? ClientType { get; set; }                 // JSON mein int (0/1) ya null
    public string? BusinessName { get; set; }
    public string? Country { get; set; }
    public string? City { get; set; }
    public string? Username { get; set; }
    public List<string> Skills { get; set; } = new();
    public List<string> DesiredJobTitles { get; set; } = new();
    public List<string> DesiredJobLocations { get; set; } = new();
    public List<string> HiringInterests { get; set; } = new();
    public HiringType? HiringType { get; set; }
    public ConnectionInvitePolicy? InvitePolicy { get; set; }
    public int ProfileCompletionPercent { get; set; }    // server-side calculated
    public UserCapabilitiesDto Capabilities { get; set; } = new();  // additive — computed
    public List<ExperienceResponseDto> Experiences { get; set; } = new();
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
