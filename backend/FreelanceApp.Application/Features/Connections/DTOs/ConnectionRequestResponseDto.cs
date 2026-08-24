using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Connections.DTOs;

public class ConnectionRequestResponseDto
{
    public Guid Id { get; set; }
    public Guid RequesterId { get; set; }
    public Guid ReceiverId { get; set; }
    public ConnectionStatus Status { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? RespondedAt { get; set; }
}
