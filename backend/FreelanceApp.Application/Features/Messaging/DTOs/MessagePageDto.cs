namespace FreelanceApp.Application.Features.Messaging.DTOs;

// Cursor pagination for messages — deliberately NOT PagedResult<T>. Messages are a
// live-appending list, so offset paging would duplicate/skip rows as new messages arrive.
// NextCursor is the CreatedAt of the oldest item in this page; pass it back as `before`
// to fetch the next (older) page. HasMore is false once no older messages remain.
public class MessagePageDto
{
    public List<MessageDto> Items { get; set; } = [];
    public DateTime? NextCursor { get; set; }
    public bool HasMore { get; set; }
}
