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
}