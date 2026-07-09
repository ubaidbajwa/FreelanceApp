namespace FreelanceApp.Application.Interfaces.Services;

public interface IFaceMatchService
{
    Task<FaceMatchResult> CompareFacesAsync(
        string sourceImageUrl,
        string targetImageUrl,
        CancellationToken ct = default);
}

public class FaceMatchResult
{
    public bool IsMatch { get; set; }
    public double SimilarityScore { get; set; }   // 0.0 - 1.0
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
}