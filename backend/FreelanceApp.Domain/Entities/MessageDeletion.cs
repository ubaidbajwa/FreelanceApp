namespace FreelanceApp.Domain.Entities;

// "Delete for me" — a per-user tombstone. Composite PK (MessageId, UserId). Its mere existence
// excludes the row from THAT user's message list; the other participant is unaffected. This is
// the deliberate contrast to "delete for everyone", which sets Message.DeletedAt (a shared
// tombstone both users see as "This message was deleted").
public class MessageDeletion
{
    public Guid MessageId { get; set; }   // composite PK part
    public Guid UserId { get; set; }      // composite PK part

    public DateTime DeletedAt { get; set; }

    // ===== Navigation Properties =====
    public Message? Message { get; set; }
}
