using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using Google.Apis.Auth;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Infrastructure.Services;

/// <summary>
/// Verifies Google ID tokens via <see cref="GoogleJsonWebSignature"/> — checks
/// the signature against Google's public keys plus issuer/expiry, and restricts
/// the audience to our configured client IDs. Fails closed (returns null).
/// </summary>
public class GoogleTokenVerifier : IGoogleTokenVerifier
{
    private readonly GoogleAuthSettings _settings;
    private readonly ILogger<GoogleTokenVerifier> _logger;

    public GoogleTokenVerifier(
        IOptions<GoogleAuthSettings> options,
        ILogger<GoogleTokenVerifier> logger)
    {
        _settings = options.Value;
        _logger = logger;
    }

    public async Task<GoogleUserPayload?> VerifyAsync(string idToken, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(idToken))
        {
            _logger.LogWarning("Google token verification failed — empty token");
            return null;
        }

        if (_settings.ClientIds is null || _settings.ClientIds.Length == 0)
        {
            // Misconfiguration — without an audience allow-list any Google user
            // could sign in. Fail closed rather than trust everything.
            _logger.LogError("GoogleAuth:ClientIds not configured — rejecting token");
            return null;
        }

        try
        {
            var validationSettings = new GoogleJsonWebSignature.ValidationSettings
            {
                Audience = _settings.ClientIds
            };

            // Validates signature, issuer (accounts.google.com) and expiry;
            // throws InvalidJwtException if anything (incl. audience) is off.
            var payload = await GoogleJsonWebSignature.ValidateAsync(idToken, validationSettings);

            return new GoogleUserPayload(
                Subject: payload.Subject,
                Email: payload.Email,
                EmailVerified: payload.EmailVerified,
                FullName: payload.Name);
        }
        catch (InvalidJwtException ex)
        {
            // Bad signature, wrong audience, expired — untrusted. (Token not logged.)
            _logger.LogWarning(ex, "Google token rejected as invalid");
            return null;
        }
        catch (Exception ex)
        {
            // Network failure fetching Google's certs, etc. — fail closed.
            _logger.LogError(ex, "Google token verification error — failing closed");
            return null;
        }
    }
}
