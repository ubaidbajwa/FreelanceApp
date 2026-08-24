namespace FreelanceApp.Application.Interfaces.Services;

public interface IImageStorageService
{
    Task<string> UploadAsync(
        Stream fileStream,
        string fileName,
        string folder,
        CancellationToken ct = default);

    // Purani image replace hone pe cleanup — URL se public id nikal kar delete.
    // Best-effort: delete fail ho to throw NAHI karta (upload flow break na ho).
    Task DeleteByUrlAsync(string imageUrl, CancellationToken ct = default);
}