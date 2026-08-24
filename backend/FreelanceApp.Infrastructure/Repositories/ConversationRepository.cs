using FreelanceApp.Application.Common.Models;
using FreelanceApp.Application.Features.Messaging.DTOs;
using FreelanceApp.Application.Interfaces.Repositories;
using FreelanceApp.Domain.Entities;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace FreelanceApp.Infrastructure.Repositories;

public class ConversationRepository : IConversationRepository
{
    private readonly AppDbContext _context;

    public ConversationRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Conversation?> GetByIdAsync(Guid id)
    {
        // Tracked — caller mutates Status/RespondedAt/LastReadAt on accept/decline/read.
        return await _context.Conversations
            .Include(c => c.Participants)
            .FirstOrDefaultAsync(c => c.Id == id);
    }

    public async Task<Conversation?> FindBetweenAsync(Guid userA, Guid userB)
    {
        // A 1:1 thread is the conversation where BOTH users are participants.
        return await _context.Conversations
            .Include(c => c.Participants)
            .FirstOrDefaultAsync(c =>
                c.Participants.Any(p => p.UserId == userA) &&
                c.Participants.Any(p => p.UserId == userB));
    }

    public async Task<PagedResult<ConversationSummaryDto>> GetAcceptedPageAsync(
        Guid userId, int page, int pageSize, CancellationToken ct = default)
    {
        // Start from MY participant rows (uses IX_ConversationParticipants_UserId), keep the
        // caller's own conversations that actually have a message (LastMessageAt != null): every
        // accepted thread, plus any still-Pending thread I myself initiated. From the sender's
        // perspective that pending thread is simply their conversation — the "request" framing is
        // the RECIPIENT's, which is why IsRequest is computed caller-relative below and stays false
        // here. A conversation opened but never messaged must not clutter either party's list.
        // Declined threads are deliberately excluded for BOTH parties: a request the recipient
        // declined should not linger in the sender's list — the sender learns from the missing reply.
        // Newest activity first; Id tiebreaker keeps paging stable.
        var baseQuery = MyConversations(userId)
            .Where(x => x.Conversation.LastMessageAt != null &&
                        (x.Conversation.Status == ConversationStatus.Accepted ||
                         (x.Conversation.Status == ConversationStatus.Pending &&
                          x.Conversation.InitiatorId == userId)));

        var totalCount = await baseQuery.CountAsync(ct);

        // Order by the plain LastMessageAt column (no COALESCE) — a plain column sort key can use
        // IX_Conversations_LastMessageAt; an expression key cannot. SAFE ONLY because the WHERE
        // above guarantees LastMessageAt != null. If that predicate is ever removed, revisit this:
        // Postgres sorts NULLs FIRST on DESC, which would float empty threads to the top.
        var items = await baseQuery
            .OrderByDescending(x => x.Conversation.LastMessageAt)
            .ThenByDescending(x => x.Conversation.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(ProjectSummary(userId))
            .ToListAsync(ct);

        return new PagedResult<ConversationSummaryDto>
        {
            Items = items,
            Page = page,
            PageSize = pageSize,
            TotalCount = totalCount
        };
    }

    public async Task<PagedResult<ConversationSummaryDto>> GetPendingRequestsPageAsync(
        Guid userId, int page, int pageSize, CancellationToken ct = default)
    {
        // Incoming requests only: Pending AND someone ELSE started it AND it carries a message
        // (LastMessageAt != null) — an empty pending thread isn't yet a real request. Newest first.
        var baseQuery = MyConversations(userId)
            .Where(x => x.Conversation.Status == ConversationStatus.Pending &&
                        x.Conversation.InitiatorId != userId &&
                        x.Conversation.LastMessageAt != null);

        var totalCount = await baseQuery.CountAsync(ct);

        // Order by plain LastMessageAt (the request's message time), consistent with the accepted
        // list and index-friendly. SAFE ONLY because the WHERE above guarantees LastMessageAt != null
        // (else NULLs would sort FIRST on DESC and float message-less threads to the top).
        var items = await baseQuery
            .OrderByDescending(x => x.Conversation.LastMessageAt)
            .ThenByDescending(x => x.Conversation.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(ProjectSummary(userId))
            .ToListAsync(ct);

        return new PagedResult<ConversationSummaryDto>
        {
            Items = items,
            Page = page,
            PageSize = pageSize,
            TotalCount = totalCount
        };
    }

    public async Task<ConversationSummaryDto?> GetSummaryByIdAsync(
        Guid conversationId, Guid userId, CancellationToken ct = default)
    {
        // Reuses the exact list projection so a single conversation's summary can't drift
        // from the list rows. Returns null if the user isn't a participant (lateral join misses).
        return await MyConversations(userId)
            .Where(x => x.Conversation.Id == conversationId)
            .Select(ProjectSummary(userId))
            .FirstOrDefaultAsync(ct);
    }

    // Base shape shared by both list flows: my participant row + its conversation + the OTHER
    // participant's user/profile. The `from other in ...Where(...)` is a lateral join (one row
    // for the 1:1 counterpart) — NOT an Include, so no Cartesian collection explosion.
    private IQueryable<ConversationRow> MyConversations(Guid userId) =>
        from cp in _context.ConversationParticipants.AsNoTracking()
        where cp.UserId == userId
        join c in _context.Conversations on cp.ConversationId equals c.Id
        from other in _context.ConversationParticipants
            .Where(o => o.ConversationId == c.Id && o.UserId != userId)
        join ou in _context.Users on other.UserId equals ou.Id
        join p in _context.Profiles on ou.Id equals p.UserId into pg
        from p in pg.DefaultIfEmpty()
        select new ConversationRow { Conversation = c, MyParticipant = cp, OtherUser = ou, OtherProfile = p };

    // Single projection reused by both pages. Correlated subqueries resolve the last-message
    // preview and unread count in the SAME statement — query count is constant, independent
    // of row count.
    private System.Linq.Expressions.Expression<Func<ConversationRow, ConversationSummaryDto>> ProjectSummary(Guid userId) =>
        x => new ConversationSummaryDto
        {
            Id = x.Conversation.Id,
            Status = x.Conversation.Status,
            // Incoming request = still pending AND started by the other side.
            IsRequest = x.Conversation.Status == ConversationStatus.Pending &&
                        x.Conversation.InitiatorId != userId,
            LastMessageAt = x.Conversation.LastMessageAt,
            OtherUser = new ConversationUserDto
            {
                UserId = x.OtherUser.Id,
                FullName = x.OtherUser.FullName,
                Headline = x.OtherProfile != null ? x.OtherProfile.Headline : null,
                PhotoUrl = x.OtherProfile != null ? x.OtherProfile.ProfilePhotoUrl : null
            },
            // Truncate to 120 chars in SQL so we never haul a full 4000-char body for a list preview.
            // System messages (empty body) are excluded — fall back to the last real content message
            // so the preview is never blank.
            LastMessagePreview = _context.Messages
                .Where(m => m.ConversationId == x.Conversation.Id && m.DeletedAt == null
                            && m.Type != MessageType.System)
                .OrderByDescending(m => m.CreatedAt).ThenByDescending(m => m.Id)
                .Select(m => m.Body.Length > 120 ? m.Body.Substring(0, 120) : m.Body)
                .FirstOrDefault(),
            // Unread = messages from the OTHER side newer than my read watermark.
            // System messages are excluded — an activity marker (pin/unpin) should not bump the
            // unread badge; it is noise, not content the recipient needs to respond to.
            UnreadCount = _context.Messages.Count(m =>
                m.ConversationId == x.Conversation.Id &&
                m.SenderId != userId &&
                m.DeletedAt == null &&
                m.Type != MessageType.System &&
                (x.MyParticipant.LastReadAt == null || m.CreatedAt > x.MyParticipant.LastReadAt))
        };

    public async Task<IReadOnlyList<MessageDto>> GetMessagesAsync(
        Guid conversationId, Guid userId, DateTime? before, int limit, CancellationToken ct = default)
    {
        // Single projection statement (replyTo resolved by correlated subquery — no per-row round-trip).
        var items = await MessagePageQuery(conversationId, userId, before, limit).ToListAsync(ct);

        // Reactions: ONE aggregate query keyed by the page's message ids, attached in memory.
        // Query count is therefore constant (projection + this one) regardless of page size.
        await AttachReactionsAsync(items, userId, ct);
        return items;
    }

    // The message-page IQueryable, exposed on the concrete repo (not the interface) so the query
    // shape can be inspected with ToQueryString() in a test. This is the single SELECT that backs a
    // page; the reactions aggregate is a separate GROUP BY (see AttachReactionsAsync).
    public IQueryable<MessageDto> MessagePageQuery(Guid conversationId, Guid userId, DateTime? before, int limit)
    {
        var query = _context.Messages
            .AsNoTracking()
            // Include "delete for everyone" tombstones (projected with a blanked body below); exclude
            // only the rows THIS caller deleted-for-me (a private, per-user hide).
            .Where(m => m.ConversationId == conversationId &&
                        !_context.MessageDeletions.Any(d => d.MessageId == m.Id && d.UserId == userId));

        // Keyset cursor: fetch messages strictly older than `before` (exclusive).
        if (before.HasValue)
            query = query.Where(m => m.CreatedAt < before.Value);

        // Newest-first page; Id tiebreaker keeps same-timestamp rows deterministic.
        return query
            .OrderByDescending(m => m.CreatedAt)
            .ThenByDescending(m => m.Id)
            .Take(limit)
            .Select(ProjectMessage(userId));
    }

    // Single message projection reused by the page, the pinned list, and single-message fetches.
    // replyTo is resolved through the ReplyToMessage reference navigation (self-FK ReplyToMessageId →
    // Messages.Id) and the quoted message's Sender navigation. EF translates both to LEFT JOINs on the
    // respective PRIMARY KEYs (unique-index seeks) in the SAME statement — NOT a windowed subquery.
    // A FirstOrDefault()/Take(1) over a correlated Where would make EF emit `ROW_NUMBER() OVER(...)`
    // inside an unfiltered `FROM "Messages"` scan whose cost grows with the whole table; there is no
    // "pick one of many" here (ReplyToMessageId is null or exactly one row), so no Take(1) is needed.
    // Reactions are attached separately (see below).
    private System.Linq.Expressions.Expression<Func<Message, MessageDto>> ProjectMessage(Guid userId) =>
        m => new MessageDto
        {
            Id = m.Id,
            ConversationId = m.ConversationId,
            SenderId = m.SenderId,
            // Blank the body for a "delete for everyone" tombstone IN SQL — the original text never
            // leaves the database.
            Body = m.DeletedAt == null ? m.Body : string.Empty,
            Type = m.Type,
            CreatedAt = m.CreatedAt,
            IsDeleted = m.DeletedAt != null,
            EditedAt = m.EditedAt,
            // A pin is active only when PinnedAt IS NOT NULL AND (PinExpiresAt IS NULL OR PinExpiresAt > now).
            // Filtering here (not in a background sweeper) is always correct and costs nothing extra
            // since the query already touches these rows.
            IsPinned = m.PinnedAt != null && (m.PinExpiresAt == null || m.PinExpiresAt > DateTime.UtcNow),
            PinnedByUserId = m.PinnedByUserId,
            PinExpiresAt = m.PinExpiresAt,
            IsForwarded = m.ForwardedFromMessageId != null,
            SystemEventType = m.SystemEventType,
            SystemTargetMessageId = m.SystemTargetMessageId,
            ReplyTo = m.ReplyToMessage == null
                ? null
                : new MessageReplyDto
                {
                    MessageId = m.ReplyToMessage.Id,
                    SenderId = m.ReplyToMessage.SenderId,
                    // Sender name via the quoted message's Sender navigation — a PK join on Users.Id.
                    SenderName = m.ReplyToMessage.Sender!.FullName ?? string.Empty,
                    // Snippet truncated to 80 chars in SQL; blank if the quoted message is a tombstone.
                    BodySnippet = m.ReplyToMessage.DeletedAt != null
                        ? string.Empty
                        : (m.ReplyToMessage.Body.Length > 80
                            ? m.ReplyToMessage.Body.Substring(0, 80)
                            : m.ReplyToMessage.Body),
                    Type = m.ReplyToMessage.Type,
                    IsDeleted = m.ReplyToMessage.DeletedAt != null
                },
            Reactions = new List<MessageReactionSummaryDto>()   // attached in memory below
        };

    // Attach aggregated reactions to a materialized page with ONE query (GROUP BY message+emoji),
    // then O(1) dictionary lookup per message. Never a collection-per-row inside the message query
    // (which would Cartesian-explode the page).
    private async Task AttachReactionsAsync(List<MessageDto> items, Guid userId, CancellationToken ct)
    {
        if (items.Count == 0) return;

        var ids = items.Select(i => i.Id).ToList();
        var rows = await _context.MessageReactions
            .AsNoTracking()
            .Where(r => ids.Contains(r.MessageId))
            .GroupBy(r => new { r.MessageId, r.Emoji })
            .Select(g => new
            {
                g.Key.MessageId,
                g.Key.Emoji,
                Count = g.Count(),
                Mine = g.Any(x => x.UserId == userId)
            })
            .ToListAsync(ct);

        var byMessage = rows
            .GroupBy(r => r.MessageId)
            .ToDictionary(g => g.Key, g => g
                .OrderByDescending(r => r.Count)
                .Select(r => new MessageReactionSummaryDto { Emoji = r.Emoji, Count = r.Count, ReactedByMe = r.Mine })
                .ToList());

        foreach (var item in items)
            if (byMessage.TryGetValue(item.Id, out var reactions))
                item.Reactions = reactions;
    }

    public async Task<int> CountMessagesBySenderAsync(Guid conversationId, Guid senderId, CancellationToken ct = default)
    {
        // Counts all non-system messages the sender authored in the thread (soft-deleted included:
        // a sent message still consumes the single pre-acceptance turn). System messages (pin/unpin
        // activity markers) are excluded so they never consume a user's message allowance.
        return await _context.Messages
            .AsNoTracking()
            .CountAsync(m => m.ConversationId == conversationId && m.SenderId == senderId
                             && m.Type != MessageType.System, ct);
    }

    public async Task<bool> AreConnectedAsync(Guid userA, Guid userB, CancellationToken ct = default)
    {
        return await _context.Connections
            .AsNoTracking()
            .AnyAsync(c => c.Status == ConnectionStatus.Accepted &&
                ((c.RequesterId == userA && c.ReceiverId == userB) ||
                 (c.RequesterId == userB && c.ReceiverId == userA)), ct);
    }

    // ===== Message actions (M1.2) =====

    public Task<Message?> GetMessageByIdAsync(Guid messageId) =>
        _context.Messages.FirstOrDefaultAsync(m => m.Id == messageId);   // tracked — mutations persist

    public async Task<MessageDto?> GetMessageDtoAsync(Guid messageId, Guid userId, CancellationToken ct = default)
    {
        var item = await _context.Messages
            .AsNoTracking()
            .Where(m => m.Id == messageId)
            .Select(ProjectMessage(userId))
            .FirstOrDefaultAsync(ct);

        if (item == null) return null;
        var list = new List<MessageDto> { item };
        await AttachReactionsAsync(list, userId, ct);
        return item;
    }

    public async Task<IReadOnlyList<Message>> GetMessagesByIdsAsync(
        Guid conversationId, IReadOnlyCollection<Guid> ids, CancellationToken ct = default) =>
        await _context.Messages
            .AsNoTracking()
            .Where(m => m.ConversationId == conversationId && ids.Contains(m.Id))
            .ToListAsync(ct);

    public async Task<IReadOnlyList<MessageDto>> GetPinnedAsync(Guid conversationId, Guid userId, CancellationToken ct = default)
    {
        // Active pins only (expiry filter). Newest-pinned first. Excludes the caller's delete-for-me rows.
        var items = await _context.Messages
            .AsNoTracking()
            .Where(m => m.ConversationId == conversationId && m.PinnedAt != null &&
                        (m.PinExpiresAt == null || m.PinExpiresAt > DateTime.UtcNow) &&
                        !_context.MessageDeletions.Any(d => d.MessageId == m.Id && d.UserId == userId))
            .OrderByDescending(m => m.PinnedAt)
            .Select(ProjectMessage(userId))
            .ToListAsync(ct);

        await AttachReactionsAsync(items, userId, ct);
        return items;
    }

    // Counts ACTIVE pins only — expired pins (PinExpiresAt <= UtcNow) are excluded so they don't
    // block new pins from being added.
    public Task<int> CountPinnedAsync(Guid conversationId, CancellationToken ct = default) =>
        _context.Messages.AsNoTracking()
            .CountAsync(m => m.ConversationId == conversationId && m.PinnedAt != null &&
                             (m.PinExpiresAt == null || m.PinExpiresAt > DateTime.UtcNow), ct);

    // Returns the oldest ACTIVE pin (lowest PinnedAt), tracked so the caller can mutate it.
    // Used by replace-oldest: finding the victim before unpinning it in the same SaveChanges.
    public Task<Message?> GetOldestActivePinAsync(Guid conversationId, CancellationToken ct = default) =>
        _context.Messages
            .Where(m => m.ConversationId == conversationId && m.PinnedAt != null &&
                        (m.PinExpiresAt == null || m.PinExpiresAt > DateTime.UtcNow))
            .OrderBy(m => m.PinnedAt)
            .FirstOrDefaultAsync(ct);

    public Task<MessageReaction?> GetReactionAsync(Guid messageId, Guid userId) =>
        _context.MessageReactions.FirstOrDefaultAsync(r => r.MessageId == messageId && r.UserId == userId);

    public async Task AddReactionAsync(MessageReaction reaction) =>
        await _context.MessageReactions.AddAsync(reaction);

    public Task RemoveReactionAsync(MessageReaction reaction)
    {
        _context.MessageReactions.Remove(reaction);
        return Task.CompletedTask;
    }

    public async Task<IReadOnlyList<MessageReactionSummaryDto>> GetReactionSummaryAsync(
        Guid messageId, Guid? me, CancellationToken ct = default) =>
        await _context.MessageReactions
            .AsNoTracking()
            .Where(r => r.MessageId == messageId)
            .GroupBy(r => r.Emoji)
            .Select(g => new MessageReactionSummaryDto
            {
                Emoji = g.Key,
                Count = g.Count(),
                ReactedByMe = me.HasValue && g.Any(x => x.UserId == me.Value)
            })
            .OrderByDescending(x => x.Count)
            .ToListAsync(ct);

    public async Task AddMessageDeletionAsync(MessageDeletion deletion) =>
        await _context.MessageDeletions.AddAsync(deletion);

    public Task<bool> HasMessageDeletionAsync(Guid messageId, Guid userId, CancellationToken ct = default) =>
        _context.MessageDeletions.AsNoTracking()
            .AnyAsync(d => d.MessageId == messageId && d.UserId == userId, ct);

    public async Task AddAsync(Conversation conversation)
    {
        await _context.Conversations.AddAsync(conversation);
    }

    public async Task AddMessageAsync(Message message)
    {
        await _context.Messages.AddAsync(message);
    }

    public async Task SaveChangesAsync()
    {
        await _context.SaveChangesAsync();
    }

    // Intermediate row for the two list projections — never materialized on its own,
    // it composes into a single SQL statement.
    private sealed class ConversationRow
    {
        public Conversation Conversation { get; set; } = null!;
        public ConversationParticipant MyParticipant { get; set; } = null!;
        public User OtherUser { get; set; } = null!;
        public Profile? OtherProfile { get; set; }
    }
}
