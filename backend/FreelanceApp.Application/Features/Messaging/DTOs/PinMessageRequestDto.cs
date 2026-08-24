using FreelanceApp.Domain.Enums;

namespace FreelanceApp.Application.Features.Messaging.DTOs;

public class PinMessageRequestDto
{
    public PinDuration Duration { get; set; }

    // When the cap is full, replace the oldest active pin instead of 409-ing.
    // Client sends true only after the user confirms the "replace oldest?" prompt.
    public bool ReplaceOldest { get; set; } = false;
}
