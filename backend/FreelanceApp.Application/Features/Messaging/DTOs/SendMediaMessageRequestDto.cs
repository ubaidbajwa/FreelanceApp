namespace FreelanceApp.Application.Features.Messaging.DTOs;

// The non-file part of a media send (multipart). The file itself is carried separately as a
// MediaUploadInput because IFormFile is an ASP.NET type the Application layer must not reference,
// and its content validation (magic bytes / size / duration) is inherently imperative — done in
// ChatService, not here. Caption is OPTIONAL for media (unlike text, where Body is required).
public class SendMediaMessageRequestDto
{
    // Optional caption. Stored as Message.Body (empty when omitted). Required-ness differs from text:
    // a media message may have no caption at all.
    public string? Caption { get; set; }

    // Optional reply target in the SAME conversation (cross-conversation target rejected in ChatService).
    public Guid? ReplyToMessageId { get; set; }

    // Optional voice waveform (M-M6): comma-separated integers, each 0–100, at most 64 samples. Only
    // meaningful for a voice note. Its SHAPE is validated server-side in ChatService (a malformed value
    // is a 400) — kept there rather than in the validator because the same method already runs the
    // file's imperative checks, and validating in one place keeps the media write path single.
    public string? Waveform { get; set; }
}
