namespace FreelanceApp.Application.Features.Connections.DTOs;

// GET /api/connections/status/{otherUserId} ka jawab.
// Values: "None" | "PendingOutgoing" | "PendingIncoming" | "Connected"
public class ConnectionStatusResponseDto
{
    public string Status { get; set; } = "None";
}
