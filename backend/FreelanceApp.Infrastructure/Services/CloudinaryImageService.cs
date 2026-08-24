using CloudinaryDotNet;
using CloudinaryDotNet.Actions;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Infrastructure.Services;

public class CloudinaryImageService : IImageStorageService
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