namespace FreelanceApp.Application.Features.Messaging.DTOs;

// Kicks off a 1:1 conversation with the recipient. The first message body is sent
// separately (SendMessageRequestDto) once the thread exists.
public class StartConversationRequestDto
{
    public Guid RecipientId { get; set; }
}
