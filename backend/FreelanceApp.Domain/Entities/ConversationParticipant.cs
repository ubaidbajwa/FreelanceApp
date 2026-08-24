namespace FreelanceApp.Domain.Entities;

// Join table (na ke UserAId/UserBId columns): M1 sirf 1:1 chahta hai, lekin group chat
// baad mein additive ban jaata hai — painful migration se bacha. Shape abhi sasti hai.
//
// LastReadAt watermark (na ke per-message read rows): 1000 messages x 2 users = 2000 rows
// sirf "seen" track karne ke liye. Watermark se unread count ek indexed query mein aata hai:
// CreatedAt > LastReadAt AND SenderId != me.
public class ConversationParticipant
{
    public Guid ConversationId { get; set; }    // composite PK ka hissa
    public Guid UserId { get; set; }             // composite PK ka hissa

    // Read-receipt watermark — null = abhi tak kuch nahi padha
    public DateTime? LastReadAt { get; set; }

    public DateTime JoinedAt { get; set; }

    // ===== Navigation Properties =====
    public Conversation? Conversation { get; set; }
    public User? User { get; set; }
}
