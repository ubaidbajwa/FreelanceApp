using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Enums;
using Google.Cloud.Vision.V1;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Text.RegularExpressions;

namespace FreelanceApp.Infrastructure.Services;

public class GoogleVisionOcrService : IOcrService
{
    private readonly ImageAnnotatorClient _client;
    private readonly ILogger<GoogleVisionOcrService> _logger;

    public GoogleVisionOcrService(
        IOptions<GoogleVisionSettings> settings,
        ILogger<GoogleVisionOcrService> logger)
    {
        var fullPath = Path.Combine(AppContext.BaseDirectory, settings.Value.CredentialsPath);
        Environment.SetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS", fullPath);
        _client = ImageAnnotatorClient.Create();
        _logger = logger;
    }

    public async Task<OcrResult> ExtractTextAsync(
        string imageUrl,
        DocumentType documentType,
        CancellationToken ct = default)
    {
        try
        {
            var image = await Image.FetchFromUriAsync(imageUrl);
            var response = await _client.DetectTextAsync(image);

            if (response.Count == 0)
                return new OcrResult { Success = false, ErrorMessage = "No text detected in image" };

            var rawText = response[0].Description;
            _logger.LogInformation("OCR extracted {Length} chars from {DocType}", rawText.Length, documentType);

            return documentType switch
            {
                DocumentType.Cnic => ExtractCnicFields(rawText),
                DocumentType.Passport => ExtractPassportFields(rawText),
                _ => ExtractGenericFields(rawText)
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "OCR failed for image: {Url}", imageUrl);
            return new OcrResult { Success = false, ErrorMessage = ex.Message };
        }
    }

    // CNIC format: 12345-6789012-3
    private static OcrResult ExtractCnicFields(string rawText)
    {
        var docNum = Regex.Match(rawText, @"\d{5}-\d{7}-\d{1}");
        var name = Regex.Match(rawText, @"Name[:\s]+([A-Z][a-zA-Z\s]+)", RegexOptions.IgnoreCase);

        return new OcrResult
        {
            RawText = rawText,
            ExtractedDocumentNumber = docNum.Success ? docNum.Value : null,
            ExtractedFullName = name.Success ? name.Groups[1].Value.Trim() : null,
            ExtractedDateOfBirth = ExtractDate(rawText),
            Success = true
        };
    }

    // Passport MRZ (TD3): line 2 starts with 9-char passport number followed by a check digit
    private static OcrResult ExtractPassportFields(string rawText)
    {
        var mrzLine2 = Regex.Match(rawText, @"([A-Z0-9<]{9})\d[A-Z]{3}\d{6}\d[MFX<]\d{6}");
        var passportNum = mrzLine2.Success ? mrzLine2.Groups[1].Value.TrimEnd('<') : null;

        var nameLine = Regex.Match(rawText, @"P<[A-Z]{3}([A-Z<]{1,39})");
        string? fullName = null;
        if (nameLine.Success)
        {
            // MRZ convention: << separates surname from given names, < is a space within each part
            var parts = nameLine.Groups[1].Value.Split("<<", 2);
            var surname = parts[0].Replace('<', ' ').Trim();
            var givenNames = parts.Length > 1 ? parts[1].Replace('<', ' ').Trim() : string.Empty;
            fullName = string.IsNullOrWhiteSpace(givenNames) ? surname : $"{givenNames} {surname}";
        }

        return new OcrResult
        {
            RawText = rawText,
            ExtractedDocumentNumber = passportNum,
            ExtractedFullName = fullName,
            ExtractedDateOfBirth = ExtractDate(rawText),
            Success = true
        };
    }

    private static OcrResult ExtractGenericFields(string rawText)
    {
        var nameMatch = Regex.Match(rawText, @"Name[:\s]+([A-Z][a-zA-Z\s]{2,40})", RegexOptions.IgnoreCase);
        var idMatch = Regex.Match(rawText, @"\b[A-Z0-9]{2,4}[-]?[A-Z0-9]{4,16}\b");

        return new OcrResult
        {
            RawText = rawText,
            ExtractedDocumentNumber = idMatch.Success ? idMatch.Value : null,
            ExtractedFullName = nameMatch.Success ? nameMatch.Groups[1].Value.Trim() : null,
            ExtractedDateOfBirth = ExtractDate(rawText),
            Success = true
        };
    }

    private static DateOnly? ExtractDate(string text)
    {
        var match = Regex.Match(text, @"(\d{2})[.\-/](\d{2})[.\-/](\d{4})");
        if (!match.Success) return null;

        if (int.TryParse(match.Groups[1].Value, out var day) &&
            int.TryParse(match.Groups[2].Value, out var month) &&
            int.TryParse(match.Groups[3].Value, out var year))
        {
            try { return new DateOnly(year, month, day); }
            catch { return null; }
        }
        return null;
    }
}
