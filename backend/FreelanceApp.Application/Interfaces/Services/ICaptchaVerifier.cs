namespace FreelanceApp.Application.Interfaces.Services;

/// <summary>
/// Server-side verification of a client-supplied captcha token (e.g. Google
/// reCAPTCHA). Implementations must fail closed on any error — a return of
/// <c>false</c> means "do not trust this request".
/// </summary>
public interface ICaptchaVerifier
{
    Task<bool> VerifyAsync(string token, CancellationToken ct);
}
