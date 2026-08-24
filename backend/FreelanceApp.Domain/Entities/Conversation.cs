using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Domain.Entities;

public class Conversation
{
    public Guid Id { get; set; }

    public ConversationStatus Status { get; set; } = ConversationStatus.Pending;

    // Kisne conversation shuru ki — "1 message tak hi request" rule enforce karne ke liye chahiye
    public Guid InitiatorId { get; set; }

    public DateTime CreatedAt { get; set; }

    // Pehle message tak null; list ordering (recent-first) isi se hota hai
    public DateTime? LastMessageAt { get; set; }

    // Accept ya Decline hone par set hota hai — null = abhi Pending
    public DateTime? RespondedAt { get; set; }

    // ===== Navigation Properties =====
    public ICollection<ConversationParticipant> Participants { get; set; } = new List<ConversationParticipant>();
    public ICollection<Message> Messages { get; set; } = new List<Message>();
}
