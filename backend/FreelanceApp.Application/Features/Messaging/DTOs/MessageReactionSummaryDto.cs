namespace FreelanceApp.Application.Features.Messaging.DTOs;

// One aggregated reaction bucket for a message: an emoji, how many people reacted with it, and
// whether the CALLER is one of them. Aggregated (GROUP BY emoji) — never a row-per-reaction list.
//
// Note on realtime: the ReactionChanged fan-out reuses this shape but with ReactedByMe = false,
// because the event goes to BOTH participants and "mine" is caller-relative — each client
// re-derives its own flag. The PUT-reaction HTTP response DOES populate ReactedByMe for the caller.
public class MessageReactionSummaryDto
{
    public string Emoji { get; set; } = string.Empty;
    public int Count { get; set; }
    public bool ReactedByMe { get; set; }
}
