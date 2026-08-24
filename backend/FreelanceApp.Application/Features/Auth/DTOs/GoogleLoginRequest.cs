namespace FreelanceApp.Application.Features.Auth.DTOs;

public class GoogleLoginRequest
{
    // The Google-issued ID token (JWT) obtained client-side after the user
    // completes Google Sign-In. Verified server-side (signature/issuer/audience)
    // before we trust any of its claims.
    public string IdToken { get; set; } = string.Empty;
}

