using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Kyc.DTOs;

public class KycUploadRequest
{
    public DocumentType DocumentType { get; set; }

    public Stream FrontImageStream { get; set; } = default!;
    public string FrontImageFileName { get; set; } = string.Empty;

    public Stream? BackImageStream { get; set; }
    public string? BackImageFileName { get; set; }

    public Stream SelfieImageStream { get; set; } = default!;
    public string SelfieImageFileName { get; set; } = string.Empty;
}