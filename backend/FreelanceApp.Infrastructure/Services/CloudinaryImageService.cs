using CloudinaryDotNet;
using CloudinaryDotNet.Actions;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Infrastructure.Services;

// Implements BOTH the simple image-URL seam (KYC / profile photos) and the richer media seam (chat
// image/video with full metadata) — one Cloudinary integration, not two upload paths.
public class CloudinaryImageService : IImageStorageService, IMediaStorageService
{
    private readonly Cloudinary _cloudinary;
    private readonly ILogger<CloudinaryImageService> _logger;

    public CloudinaryImageService(
        IOptions<CloudinarySettings> settings,
        ILogger<CloudinaryImageService> logger)
    {
        var config = settings.Value;
        var account = new Account(config.CloudName, config.ApiKey, config.ApiSecret);
        _cloudinary = new Cloudinary(account);
        _logger = logger;
    }

    public async Task<string> UploadAsync(
        Stream fileStream,
        string fileName,
        string folder,
        CancellationToken ct = default)
    {
        var uploadParams = new ImageUploadParams
        {
            File = new FileDescription(fileName, fileStream),
            Folder = folder,
            UseFilename = false,        // Cloudinary apna unique name dega
            UniqueFilename = true,
            Overwrite = false
        };

        var result = await _cloudinary.UploadAsync(uploadParams, ct);

        if (result.Error != null)
        {
            _logger.LogError("Cloudinary upload failed: {Error}", result.Error.Message);
            throw new Exception($"Image upload failed: {result.Error.Message}");
        }

        _logger.LogInformation("Image uploaded: {Url}", result.SecureUrl);
        return result.SecureUrl.ToString();
    }

    // Best-effort delete — replace flow ko kabhi fail nahi karna chahiye,
    // isliye error sirf log hota hai, throw nahi
    public async Task DeleteByUrlAsync(string imageUrl, CancellationToken ct = default)
    {
        var publicId = ExtractPublicId(imageUrl);
        if (publicId == null)
        {
            _logger.LogWarning("Could not extract Cloudinary public id from URL: {Url}", imageUrl);
            return;
        }

        try
        {
            var result = await _cloudinary.DestroyAsync(new DeletionParams(publicId));

            if (result.Error != null || result.Result != "ok")
                _logger.LogWarning("Cloudinary delete failed for {PublicId}: {Error}",
                    publicId, result.Error?.Message ?? result.Result);
            else
                _logger.LogInformation("Cloudinary image deleted: {PublicId}", publicId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Cloudinary delete threw for {PublicId}", publicId);
        }
    }

    // ===== IMediaStorageService (chat media, M-M4) =====

    public async Task<MediaUploadResult> UploadImageAsync(
        Stream content, string fileName, string folder, CancellationToken ct = default)
    {
        var uploadParams = new ImageUploadParams
        {
            File = new FileDescription(fileName, content),
            Folder = folder,
            UseFilename = false,
            UniqueFilename = true,
            Overwrite = false
        };

        var result = await _cloudinary.UploadAsync(uploadParams, ct);
        if (result.Error != null)
        {
            _logger.LogError("Cloudinary image upload failed: {Error}", result.Error.Message);
            throw new Exception($"Image upload failed: {result.Error.Message}");
        }

        return new MediaUploadResult
        {
            SecureUrl = result.SecureUrl.ToString(),
            // Thumbnail = a resized, quality-reduced variant of the SAME asset (Cloudinary URL
            // transformation) so a chat with thirty photos pulls thirty small thumbnails, not full files.
            // Transformation string: "c_fill,w_400,q_auto".
            ThumbnailUrl = BuildImageThumbnailUrl(result.SecureUrl.ToString()),
            PublicId = result.PublicId,
            Width = result.Width,
            Height = result.Height,
            DurationMs = null,
            Bytes = result.Bytes
        };
    }

    public async Task<MediaUploadResult> UploadVideoAsync(
        Stream content, string fileName, string folder, CancellationToken ct = default)
    {
        var uploadParams = new VideoUploadParams
        {
            File = new FileDescription(fileName, content),
            Folder = folder,
            UseFilename = false,
            UniqueFilename = true,
            Overwrite = false
        };

        var result = await _cloudinary.UploadAsync(uploadParams, ct);
        if (result.Error != null)
        {
            _logger.LogError("Cloudinary video upload failed: {Error}", result.Error.Message);
            throw new Exception($"Video upload failed: {result.Error.Message}");
        }

        return new MediaUploadResult
        {
            SecureUrl = result.SecureUrl.ToString(),
            // Video poster via URL transformation (NO ffmpeg / server-side processing).
            // Transformation string: "so_0,w_400,c_fill" with a ".jpg" extension.
            ThumbnailUrl = BuildVideoThumbnailUrl(result.SecureUrl.ToString()),
            PublicId = result.PublicId,
            Width = result.Width,
            Height = result.Height,
            DurationMs = double.IsNaN(result.Duration) ? null : (int)Math.Round(result.Duration * 1000),
            Bytes = result.Bytes
        };
    }

    public async Task<MediaUploadResult> UploadAudioAsync(
        Stream content, string fileName, string folder, CancellationToken ct = default)
    {
        // Audio has no distinct Cloudinary resource type — it is uploaded as VIDEO. VideoUploadParams
        // sets resource_type=video, which is exactly what Cloudinary expects for m4a/aac/ogg/webm audio.
        // No thumbnail (no poster for audio) and no width/height — only URL, duration, size, public id.
        var uploadParams = new VideoUploadParams
        {
            File = new FileDescription(fileName, content),
            Folder = folder,
            UseFilename = false,
            UniqueFilename = true,
            Overwrite = false
        };

        var result = await _cloudinary.UploadAsync(uploadParams, ct);
        if (result.Error != null)
        {
            _logger.LogError("Cloudinary audio upload failed: {Error}", result.Error.Message);
            throw new Exception($"Audio upload failed: {result.Error.Message}");
        }

        return new MediaUploadResult
        {
            SecureUrl = result.SecureUrl.ToString(),
            ThumbnailUrl = string.Empty,   // no poster for a voice note — ChatService maps this to null
            PublicId = result.PublicId,
            Width = 0,
            Height = 0,
            DurationMs = double.IsNaN(result.Duration) ? null : (int)Math.Round(result.Duration * 1000),
            Bytes = result.Bytes
        };
    }

    public async Task<MediaUploadResult> UploadDocumentAsync(
        Stream content, string fileName, string folder, CancellationToken ct = default)
    {
        // Documents upload as RAW (RawUploadParams sets resource_type=raw): Cloudinary stores the bytes
        // verbatim, so no image/document transformation pipeline ever touches attacker-supplied files —
        // the server only stores and serves them (see ADR 0004 §10). No thumbnail, no dimensions, no
        // duration for a document — only URL, size and public id are meaningful.
        var uploadParams = new RawUploadParams
        {
            File = new FileDescription(fileName, content),
            Folder = folder,
            UseFilename = false,
            UniqueFilename = true,
            Overwrite = false
        };

        // resource_type=raw: store the bytes verbatim, no transformation pipeline touches them.
        var result = await _cloudinary.UploadAsync(uploadParams, "raw", ct);
        if (result.Error != null)
        {
            _logger.LogError("Cloudinary document upload failed: {Error}", result.Error.Message);
            throw new Exception($"Document upload failed: {result.Error.Message}");
        }

        return new MediaUploadResult
        {
            SecureUrl = result.SecureUrl.ToString(),
            ThumbnailUrl = string.Empty,   // no poster for a document — ChatService maps this to null
            PublicId = result.PublicId,
            Width = 0,
            Height = 0,
            DurationMs = null,
            Bytes = result.Bytes
        };
    }

    public async Task DeleteAsync(string publicId, MediaKind kind, CancellationToken ct = default)
    {
        try
        {
            var result = await _cloudinary.DestroyAsync(new DeletionParams(publicId)
            {
                // Delete must pass the SAME resource type the asset was uploaded under, or Cloudinary
                // silently no-ops and leaves an orphan. Audio is stored under Video; documents under Raw.
                ResourceType = kind switch
                {
                    MediaKind.Video or MediaKind.Audio => ResourceType.Video,
                    MediaKind.Document => ResourceType.Raw,
                    _ => ResourceType.Image
                }
            });
            if (result.Error != null || result.Result != "ok")
                _logger.LogWarning("Cloudinary media delete failed for {PublicId}: {Error}",
                    publicId, result.Error?.Message ?? result.Result);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Cloudinary media delete threw for {PublicId}", publicId);
        }
    }

    // Inject the image thumbnail transformation immediately after "/image/upload/". A resized (w_400),
    // filled (c_fill), auto-quality (q_auto) variant of the same asset.
    private static string BuildImageThumbnailUrl(string secureUrl) =>
        secureUrl.Replace("/image/upload/", "/image/upload/c_fill,w_400,q_auto/");

    // Build a video POSTER: inject "so_0,w_400,c_fill" after "/video/upload/" (start-offset 0 frame,
    // width 400, fill) and swap the extension to ".jpg" so Cloudinary renders a still image.
    private static string BuildVideoThumbnailUrl(string secureUrl)
    {
        var withTransform = secureUrl.Replace("/video/upload/", "/video/upload/so_0,w_400,c_fill/");
        var lastSlash = withTransform.LastIndexOf('/');
        var lastDot = withTransform.LastIndexOf('.');
        return lastDot > lastSlash ? withTransform[..lastDot] + ".jpg" : withTransform + ".jpg";
    }

    // URL format: https://res.cloudinary.com/<cloud>/image/upload/v123456/folder/name.jpg
    // public id = "folder/name" (version prefix aur extension ke baghair)
    private static string? ExtractPublicId(string imageUrl)
    {
        if (!Uri.TryCreate(imageUrl, UriKind.Absolute, out var uri))
            return null;

        var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);

        var uploadIndex = Array.IndexOf(segments, "upload");
        if (uploadIndex < 0 || uploadIndex >= segments.Length - 1)
            return null;

        // "upload" ke baad optional version segment (v123456) skip karo
        var start = uploadIndex + 1;
        if (start < segments.Length && segments[start].Length > 1 &&
            segments[start][0] == 'v' && segments[start][1..].All(char.IsDigit))
            start++;

        if (start >= segments.Length)
            return null;

        var path = string.Join('/', segments[start..]);
        var dotIndex = path.LastIndexOf('.');
        return dotIndex > 0 ? path[..dotIndex] : path;
    }
}