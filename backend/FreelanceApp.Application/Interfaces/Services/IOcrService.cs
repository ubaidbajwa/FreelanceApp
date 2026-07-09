using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Interfaces.Services;

public interface IOcrService
{
    Task<OcrResult> ExtractTextAsync(
        string imageUrl,
        DocumentType documentType,
        CancellationToken ct = default);
}

public class OcrResult
{
    public string RawText { get; set; } = string.Empty;
    public string? ExtractedFullName { get; set; }
    public string? ExtractedDocumentNumber { get; set; }
    public DateOnly? ExtractedDateOfBirth { get; set; }
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
}