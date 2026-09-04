using System.ComponentModel.DataAnnotations;

namespace FreelanceApp.Api.Models;

// Multipart form for POST /api/conversations/{id}/messages/media. IFormFile lives in the API layer
// only (the Application layer must not reference ASP.NET types); the controller converts it into a
// MediaUploadInput before calling ChatService. Mirrors KycUploadApiRequest.
public class SendMediaMessageApiRequest
{
    [Required]
    public IFormFile File { get; set; } = default!;

    // Optional caption and optional reply target (same conversation).
    public string? Caption { get; set; }
    public Guid? ReplyToMessageId { get; set; }

    // Optional voice waveform (M-M6): comma-separated ints 0–100, ≤64 samples. Shape validated in ChatService.
    public string? Waveform { get; set; }
}
