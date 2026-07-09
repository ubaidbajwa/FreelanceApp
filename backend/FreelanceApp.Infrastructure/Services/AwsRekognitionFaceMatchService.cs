using Amazon;
using Amazon.Rekognition;
using Amazon.Rekognition.Model;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Infrastructure.Services;

public class AwsRekognitionFaceMatchService : IFaceMatchService
{
    private readonly AmazonRekognitionClient _client;
    private readonly AwsRekognitionSettings _settings;
    private readonly ILogger<AwsRekognitionFaceMatchService> _logger;

    public AwsRekognitionFaceMatchService(
        IOptions<AwsRekognitionSettings> options,
        ILogger<AwsRekognitionFaceMatchService> logger)
    {
        _settings = options.Value;
        _logger = logger;

        var region = RegionEndpoint.GetBySystemName(_settings.Region);
        _client = new AmazonRekognitionClient(
            _settings.AccessKeyId,
            _settings.SecretAccessKey,
            region);
    }

    public async Task<FaceMatchResult> CompareFacesAsync(
        string sourceImageUrl,
        string targetImageUrl,
        CancellationToken ct = default)
    {
        try
        {
            // Download images from Cloudinary URLs
            using var httpClient = new HttpClient();
            var sourceBytes = await httpClient.GetByteArrayAsync(sourceImageUrl, ct);
            var targetBytes = await httpClient.GetByteArrayAsync(targetImageUrl, ct);

            var request = new CompareFacesRequest
            {
                SourceImage = new Image { Bytes = new MemoryStream(sourceBytes) },
                TargetImage = new Image { Bytes = new MemoryStream(targetBytes) },
                SimilarityThreshold = (float)_settings.ManualReviewThreshold   // 60% — lowest cutoff
            };

            var response = await _client.CompareFacesAsync(request, ct);

            if (response.FaceMatches.Count == 0)
            {
                _logger.LogWarning("No matching face found between images");
                return new FaceMatchResult
                {
                    IsMatch = false,
                    SimilarityScore = 0.0,
                    Success = true,
                    ErrorMessage = "No matching face detected"
                };
            }

            // Pehla match = best match
            var topMatch = response.FaceMatches[0];
            var similarity = (topMatch.Similarity ?? 0f) / 100.0;  // Convert 0-100 to 0-1

            _logger.LogInformation("Face match score: {Score:F2}", similarity);

            return new FaceMatchResult
            {
                IsMatch = similarity >= (_settings.AutoVerifyThreshold / 100.0),
                SimilarityScore = similarity,
                Success = true
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Face match failed");
            return new FaceMatchResult
            {
                Success = false,
                ErrorMessage = ex.Message
            };
        }
    }
}