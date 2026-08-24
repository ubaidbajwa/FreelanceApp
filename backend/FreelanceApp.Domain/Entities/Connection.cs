using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Domain.Entities;

public class Connection
{
    public Guid Id { get; set; }
    public Guid RequesterId { get; set; }       // FK to User — jis ne request bheji
    public Guid ReceiverId { get; set; }        // FK to User — jise request mili

    public ConnectionStatus Status { get; set; } = ConnectionStatus.Pending;

    public DateTime CreatedAt { get; set; }
    public DateTime? RespondedAt { get; set; }  // null = abhi Pending

    // ===== Navigation Properties =====
    public User? Requester { get; set; }
    public User? Receiver { get; set; }
}
