namespace FreelanceApp.Application.Interfaces.Services;

// Media (image/video) upload seam for chat. Deliberately separate from IImageStorageService (which
// returns only a URL for KYC/profile photos) because chat needs the full metadata Cloudinary returns
// on upload — dimensions (so the client reserves layout space), duration (video), size, and the
// public id (for later deletion). The SAME CloudinaryImageService implements BOTH interfaces, so there
// is ONE Cloudinary integration, not a second upload path.
public interface IMediaStorageService
{
    /// <summary>Upload an image and return its metadata plus a resized thumbnail transformation URL.</summary>
    Task<MediaUploadResult> UploadImageAsync(Stream content, string fileName, string folder, CancellationToken ct = default);

    /// <summary>
    /// Upload a video and return its metadata (incl. DurationMs) plus a poster (so_0) thumbnail URL.
    /// No server-side transcoding — the poster is a Cloudinary URL transformation, not a generated file.
    /// </summary>
    Task<MediaUploadResult> UploadVideoAsync(Stream content, string fileName, string folder, CancellationToken ct = default);

    /// <summary>
    /// Upload a voice note (audio) and return its metadata (incl. DurationMs). Cloudinary stores audio
    /// under its VIDEO resource type, so this reuses the video upload path — no separate resource kind.
    /// No thumbnail and no dimensions (audio has none); the client draws the waveform it computed.
    /// </summary>
    Task<MediaUploadResult> UploadAudioAsync(Stream content, string fileName, string folder, CancellationToken ct = default);

    /// <summary>
    /// Upload a document (PDF / Office / text) as a Cloudinary RAW asset (resource_type=raw), so no
    /// image or document transformation pipeline ever touches attacker-supplied bytes — the server only
    /// stores and serves them. No thumbnail, no dimensions and no duration (a document has none); only
    /// URL, size and public id are returned. The original filename is preserved separately on the message
    /// (see Message.MediaFileName) — this method's fileName is only Cloudinary's upload hint.
    /// </summary>
    Task<MediaUploadResult> UploadDocumentAsync(Stream content, string fileName, string folder, CancellationToken ct = default);

    /// <summary>
    /// Best-effort delete of a just-uploaded asset. Used ONLY to clean up an over-duration video that
    /// was rejected after upload (no message references it yet). Never used for delete-for-everyone —
    /// a forwarded copy shares the public id, so deleting would break the other copy (see docs/TODO.md).
    /// </summary>
    Task DeleteAsync(string publicId, MediaKind kind, CancellationToken ct = default);
}

public enum MediaKind
{
    Image,
    Video,
    // Voice notes (M-M6). Cloudinary has no distinct "audio" resource type — audio lives under Video —
    // so this maps to ResourceType.Video for both upload and delete, but the app models it separately
    // so a Voice message is never confused with a Video message.
    Audio,
    // Documents (M-M8): PDF, Office (OOXML + OLE2), text/csv. Cloudinary's RAW resource type stores the
    // bytes verbatim with no transformation pipeline — this maps to ResourceType.Raw for both upload
    // (RawUploadParams) and delete. Modelled as its own kind so a File message is never confused with
    // an image/video/voice, and so the extension/MIME/magic-byte allowlist can key off it.
    Document
}

// What Cloudinary returns for a chat upload. ThumbnailUrl is built by the Infrastructure implementation
// (Cloudinary URL-transformation), keeping the Application layer Cloudinary-agnostic.
public sealed class MediaUploadResult
{
    public required string SecureUrl { get; init; }
    public required string ThumbnailUrl { get; init; }
    public required string PublicId { get; init; }
    public int Width { get; init; }
    public int Height { get; init; }
    public int? DurationMs { get; init; }   // video only
    public long Bytes { get; init; }
}

// A validated inbound media file handed to ChatService by the controller. Content MUST be seekable —
// ChatService peeks the leading magic bytes and rewinds to 0 before the upload reads the whole stream.
public sealed class MediaUploadInput
{
    public required Stream Content { get; init; }
    public required string FileName { get; init; }
    public required string ContentType { get; init; }   // declared MIME — validated against magic bytes
    public required long Length { get; init; }
}
