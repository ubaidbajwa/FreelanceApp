using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Domain.Entities;

public class Profile
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }            // FK to User — one profile per user (unique)

    public string DisplayName { get; set; } = string.Empty;   // create pe User.FullName se prefill
    public string? Headline { get; set; }
    public string? Bio { get; set; }
    public string? ProfilePhotoUrl { get; set; }
    public decimal? HourlyRate { get; set; }

    // Nullable — naya profile sach mein "empty" hota hai; user set kare tab value aaye
    public Availability? Availability { get; set; }
    public WorkPreference? WorkPreference { get; set; }
    public AvailabilityStatus? AvailabilityStatus { get; set; }

    // Client "About you" — Individual ya Business. BusinessName sirf Business ke liye
    // (freelancer Experience.Company se alag concept: ye client apni company hai).
    public ClientType? ClientType { get; set; }
    public string? BusinessName { get; set; }

    public string? Country { get; set; }
    public string? City { get; set; }

    // UNIQUE (case-insensitive) — hamesha lowercase store hota hai
    public string? Username { get; set; }

    // Postgres text[] columns — Npgsql List<string> ko natively map karta hai
    public List<string> Skills { get; set; } = new();

    // Job preferences (max 5 each) — job feed matching ke liye
    public List<string> DesiredJobTitles { get; set; } = new();
    public List<string> DesiredJobLocations { get; set; } = new();

    // Client hiring interests (max 5) — freelancer recommendation engine ke liye
    // DesiredJobTitles se alag: ye CLIENT ka "kya hire karna chahta hoon" hai, freelancer ka "kya kaam chahiye" nahi
    public List<string> HiringInterests { get; set; } = new();
    public HiringType? HiringType { get; set; }

    // null == Everyone (open default — existing and new users are never blocked by an unset value)
    public ConnectionInvitePolicy? InvitePolicy { get; set; }

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    // ===== Navigation Properties =====
    public User? User { get; set; }
    public List<Experience> Experiences { get; set; } = new();
}
