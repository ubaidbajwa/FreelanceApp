using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Profiles.DTOs;

// PARTIAL update — sab fields nullable; sirf non-null fields apply hoti hain.
// Username yahan NAHI hai — uska apna endpoint hai (PUT /api/profile/username).
public class UpdateProfileRequestDto
{
    public string? DisplayName { get; set; }
    public string? Headline { get; set; }
    public string? Bio { get; set; }
    public decimal? HourlyRate { get; set; }
    public Availability? Availability { get; set; }
    public WorkPreference? WorkPreference { get; set; }
    public AvailabilityStatus? AvailabilityStatus { get; set; }
    public ClientType? ClientType { get; set; }
    public string? BusinessName { get; set; }
    public string? Country { get; set; }
    public string? City { get; set; }

    // null = untouched; empty list = saari entries clear
    public List<string>? Skills { get; set; }
    public List<string>? DesiredJobTitles { get; set; }
    public List<string>? DesiredJobLocations { get; set; }

    // Client hiring interests (max 5) + hiring type
    public List<string>? HiringInterests { get; set; }
    public HiringType? HiringType { get; set; }

    // null = untouched (partial-update semantics — only set this field to change policy)
    public ConnectionInvitePolicy? InvitePolicy { get; set; }
}
