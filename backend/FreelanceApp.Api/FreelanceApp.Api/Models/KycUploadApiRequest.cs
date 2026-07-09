using FreelanceApp.Domain.Enums;
using System.ComponentModel.DataAnnotations;

namespace FreelanceApp.Api.Models;

public class KycUploadApiRequest
{
    [Required]
    public DocumentType DocumentType { get; set; }

    [Required]
    public IFormFile FrontImage { get; set; } = default!;

    public IFormFile? BackImage { get; set; }

    [Required]
    public IFormFile SelfieImage { get; set; } = default!;
}