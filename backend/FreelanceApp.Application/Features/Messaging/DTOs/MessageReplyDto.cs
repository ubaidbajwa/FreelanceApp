using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Messaging.DTOs;

// A compact snapshot of the quoted message shown above a reply. Resolved via a correlated
// subquery inside the message projection (no N+1). The snippet is truncated in SQL so a reply
// to a 4000-char message never hauls the full body just to render a preview.
public class MessageReplyDto
{
    public Guid MessageId { get; set; }
    public Guid SenderId { get; set; }
    public string SenderName { get; set; } = string.Empty;

    // Truncated (~80 chars) preview of the quoted body. Blank when the quoted message was deleted.
    public string BodySnippet { get; set; } = string.Empty;

    public MessageType Type { get; set; }

    // True when the quoted message itself was deleted-for-everyone — the client shows a
    // "message deleted" placeholder in the quote instead of the (blanked) snippet.
    public bool IsDeleted { get; set; }
}
