namespace FreelanceApp.Application.Features.People.DTOs;

// Public-facing directory row — no email/secrets, sirf profile ke public fields.
// connectionStatus vocabulary connections slice jaisa hi: None | PendingOutgoing |
// PendingIncoming | Connected — taake frontend seedha button render kar sake.
public class PersonDto
{
    public Guid UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string? Headline { get; set; }
    public string? PhotoUrl { get; set; }
    public string ConnectionStatus { get; set; } = "None";
}
