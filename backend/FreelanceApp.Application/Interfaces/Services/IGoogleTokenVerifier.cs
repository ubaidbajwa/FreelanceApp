namespace FreelanceApp.Application.Interfaces.Services;

/// <summary>
/// Validates a Google-issued ID token (signature, issuer, audience, expiry)
/// and returns the trusted user claims. Returns <c>null</c> for any invalid
/// or untrusted token — never throws for a bad token.
/// </summary>
public interface IGoogleTokenVerifier
{
    Task<GoogleUserPayload?> VerifyAsync(string idToken, CancellationToken ct);
}

/// <summary>
/// The subset of validated Google claims the app needs. <see cref="Subject"/>
/// is Google's stable user id ("sub") — maps to <c>User.ExternalId</c>.
/// </summary>
public record GoogleUserPayload(
    string Subject,
    string Email,
    bool EmailVerified,
    string? FullName);
