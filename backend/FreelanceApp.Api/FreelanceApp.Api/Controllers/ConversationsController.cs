using FreelanceApp.Api.Models;
using FreelanceApp.Application.Features.Messaging.DTOs;
using FreelanceApp.Application.Features.Messaging.Services;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/conversations")]
[Authorize]
public class ConversationsController(IChatService chatService) : ControllerBase
{
    // Caller identity comes from ICurrentUserService inside ChatService — no userId plumbing here.

    // ===== START / GET =====

    [HttpPost]
    public async Task<IActionResult> StartOrGet(
        [FromBody] StartConversationRequestDto dto, CancellationToken ct)
    {
        // Get-or-create — 200 (not 201) because an existing thread is often returned.
        var summary = await chatService.StartOrGetConversationAsync(dto.RecipientId, ct);
        return Ok(summary);
    }

    // Fetch a single conversation from the caller's perspective. Resolves a cold deep link or a
    // push-notification tap (no in-app state), and lets the client refetch on any 403 to render
    // whatever state comes back (declined-meanwhile vs one-message-rule) without an error taxonomy.
    // 200 participant · 403 outsider · 404 unknown id.
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetConversation(Guid id, CancellationToken ct)
    {
        var summary = await chatService.GetConversationAsync(id, ct);
        return Ok(summary);
    }

    // ===== LISTS =====

    [HttpGet]
    public async Task<IActionResult> GetConversations(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var result = await chatService.GetConversationsAsync(page, pageSize, ct);
        return Ok(result);
    }

    [HttpGet("requests")]
    public async Task<IActionResult> GetRequests(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var result = await chatService.GetRequestsAsync(page, pageSize, ct);
        return Ok(result);
    }

    // ===== MESSAGES =====

    [HttpGet("{id:guid}/messages")]
    public async Task<IActionResult> GetMessages(
        Guid id,
        [FromQuery] DateTime? before = null,
        [FromQuery] int limit = 30,
        CancellationToken ct = default)
    {
        var page = await chatService.GetMessagesAsync(id, before, limit, ct);
        return Ok(page);
    }

    [HttpPost("{id:guid}/messages")]
    public async Task<IActionResult> SendMessage(
        Guid id, [FromBody] SendMessageRequestDto dto, CancellationToken ct)
    {
        var message = await chatService.SendMessageAsync(id, dto, ct);
        return Created(string.Empty, message);   // 201
    }

    // Send an image/video in ONE request (multipart). The file is uploaded to Cloudinary and the
    // message created in the same request, so a file only exists if a message exists. RequestSizeLimit
    // lifts Kestrel's default 30 MB cap to the 50 MB video limit; ChatService enforces the real per-kind
    // limits (10 MB image / 50 MB video), the allowed types, magic bytes, and the 120 s video duration.
    [HttpPost("{id:guid}/messages/media")]
    [RequestSizeLimit(52_428_800)]                                    // 50 MB
    [RequestFormLimits(MultipartBodyLengthLimit = 52_428_800)]       // 50 MB
    public async Task<IActionResult> SendMediaMessage(
        Guid id, [FromForm] SendMediaMessageApiRequest apiRequest, CancellationToken ct)
    {
        var file = apiRequest.File;
        if (file is null || file.Length == 0)
            throw new Application.Exceptions.ValidationException("A media file is required.");

        var input = new MediaUploadInput
        {
            Content = file.OpenReadStream(),
            FileName = file.FileName,
            ContentType = file.ContentType ?? string.Empty,
            Length = file.Length
        };
        var request = new SendMediaMessageRequestDto
        {
            Caption = apiRequest.Caption,
            ReplyToMessageId = apiRequest.ReplyToMessageId,
            Waveform = apiRequest.Waveform
        };

        var message = await chatService.SendMediaMessageAsync(id, request, input, ct);
        return Created(string.Empty, message);   // 201
    }

    // ===== ACCEPT / DECLINE / READ =====

    [HttpPost("{id:guid}/accept")]
    public async Task<IActionResult> Accept(Guid id, CancellationToken ct)
    {
        await chatService.AcceptAsync(id, ct);
        return NoContent();
    }

    [HttpPost("{id:guid}/decline")]
    public async Task<IActionResult> Decline(Guid id, CancellationToken ct)
    {
        await chatService.DeclineAsync(id, ct);
        return NoContent();
    }

    [HttpPost("{id:guid}/read")]
    public async Task<IActionResult> MarkRead(Guid id, CancellationToken ct)
    {
        await chatService.MarkReadAsync(id, ct);
        return NoContent();
    }

    // ===== MESSAGE ACTIONS (M1.2) =====

    // Set or replace the caller's reaction. Returns the caller-relative aggregate.
    [HttpPut("{id:guid}/messages/{messageId:guid}/reaction")]
    public async Task<IActionResult> React(
        Guid id, Guid messageId, [FromBody] ReactRequestDto dto, CancellationToken ct)
    {
        var reactions = await chatService.ReactAsync(id, messageId, dto.Emoji, ct);
        return Ok(reactions);
    }

    // Remove the caller's reaction (idempotent).
    [HttpDelete("{id:guid}/messages/{messageId:guid}/reaction")]
    public async Task<IActionResult> RemoveReaction(Guid id, Guid messageId, CancellationToken ct)
    {
        await chatService.RemoveReactionAsync(id, messageId, ct);
        return NoContent();
    }

    // Edit an own message within the edit window. Returns the updated message.
    [HttpPut("{id:guid}/messages/{messageId:guid}")]
    public async Task<IActionResult> EditMessage(
        Guid id, Guid messageId, [FromBody] EditMessageRequestDto dto, CancellationToken ct)
    {
        var message = await chatService.EditMessageAsync(id, messageId, dto.Body, ct);
        return Ok(message);
    }

    // Pin a message with a chosen duration. 409 at cap (ReplaceOldest=false); atomically replaces
    // oldest active pin when ReplaceOldest=true.
    [HttpPost("{id:guid}/messages/{messageId:guid}/pin")]
    public async Task<IActionResult> Pin(
        Guid id, Guid messageId, [FromBody] PinMessageRequestDto dto, CancellationToken ct)
    {
        await chatService.PinAsync(id, messageId, dto, ct);
        return NoContent();
    }

    [HttpDelete("{id:guid}/messages/{messageId:guid}/pin")]
    public async Task<IActionResult> Unpin(Guid id, Guid messageId, CancellationToken ct)
    {
        await chatService.UnpinAsync(id, messageId, ct);
        return NoContent();
    }

    [HttpGet("{id:guid}/pinned")]
    public async Task<IActionResult> GetPinned(Guid id, CancellationToken ct)
    {
        var pinned = await chatService.GetPinnedAsync(id, ct);
        return Ok(pinned);
    }

    // Delete a message. scope is REQUIRED — no default, because defaulting either way silently
    // does the wrong thing half the time. everyone → shared tombstone; me → private per-user hide.
    [HttpDelete("{id:guid}/messages/{messageId:guid}")]
    public async Task<IActionResult> DeleteMessage(
        Guid id, Guid messageId, [FromQuery] string? scope, CancellationToken ct)
    {
        switch (scope)
        {
            case "everyone":
                await chatService.DeleteForEveryoneAsync(id, messageId, ct);
                break;
            case "me":
                await chatService.DeleteForMeAsync(id, messageId, ct);
                break;
            default:
                throw new Application.Exceptions.ValidationException(
                    "Query parameter 'scope' is required and must be 'everyone' or 'me'.");
        }
        return NoContent();
    }

    // Forward one or more of THIS conversation's messages into a target conversation.
    [HttpPost("{id:guid}/messages/forward")]
    public async Task<IActionResult> Forward(
        Guid id, [FromBody] ForwardMessagesRequestDto dto, CancellationToken ct)
    {
        var created = await chatService.ForwardAsync(id, dto, ct);
        return Ok(created);
    }

    // Mark a voice note as played by the caller. Idempotent — a second call is a no-op. 204 on success;
    // 403 outsider · 404 unknown message · 400 non-voice / own note / tombstoned.
    [HttpPost("{id:guid}/messages/{messageId:guid}/played")]
    public async Task<IActionResult> MarkPlayed(Guid id, Guid messageId, CancellationToken ct)
    {
        await chatService.MarkPlayedAsync(id, messageId, ct);
        return NoContent();
    }
}
