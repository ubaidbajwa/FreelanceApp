namespace FreelanceApp.Application.Interfaces.Services;

public interface IImageStorageService
{
    Task<string> UploadAsync(
        Stream fileStream,
        string fileName,
        string folder,
        CancellationToken ct = default);
}