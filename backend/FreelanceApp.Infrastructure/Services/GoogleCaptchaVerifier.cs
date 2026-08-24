using System.Net.Http.Json;
using System.Text.Json.Serialization;
using FreelanceApp.Application.Common.Settings;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FreelanceApp.Infrastructure.Services;

/// <summary>
/// Verifies a reCAPTCHA v2 (checkbox) token against Google's siteverify
/// endpoint using a typed <see cref="HttpClient"/>. Fails closed: any error,
/// timeout, or rejected response returns <c>false</c>.
/// </summary>
public class GoogleCaptchaVerifier : ICaptchaVerifier
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    private readonly HttpClient _httpClient;
    private readonly CaptchaOptions _options;
    private readonly ILogger<GoogleCaptchaVerifier> _logger;

    public GoogleCaptchaVerifier(
        HttpClient httpClient,
        IOptions<CaptchaOptions> options,
        ILogger<GoogleCaptchaVerifier> logger)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<bool> VerifyAsync(string token, CancellationToken ct)
    {
        // Dev bypass — keeps local/emulator signup working without a live captcha.
        if (!_options.Enabled)
        {
            _logger.LogWarning("Captcha bypassed (dev)");
            return true;
        }

        // No token → nothing to verify. Fail closed. (Token value never logged.)
        if (string.IsNullOrWhiteSpace(token))
        {
            _logger.LogWarning("Captcha verification failed — empty token");
            return false;
        }

        // 5s hard cap on the round-trip, linked to the caller's token.
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(Timeout);

        try
        {
            using var content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["secret"] = _options.SecretKey,
                ["response"] = token
            });

            using var response = await _httpClient.PostAsync(_options.VerifyEndpoint, content, cts.Token);
            response.EnsureSuccessStatusCode();

            var result = await response.Content.ReadFromJsonAsync<SiteVerifyResponse>(cts.Token);

            if (result is null || !result.Success)
            {
                _logger.LogWarning(
                    "Captcha verification rejected by provider. Errors: {Errors}",
                    result?.ErrorCodes is { Length: > 0 } e ? string.Join(",", e) : "none");
                return false;
            }

            return true;
        }
        catch (Exception ex)
        {
            // Network failure, timeout, non-2xx, malformed body — fail closed.
            _logger.LogError(ex, "Captcha verification error — failing closed");
            return false;
        }
    }

    private sealed class SiteVerifyResponse
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("error-codes")]
        public string[]? ErrorCodes { get; set; }
    }
}
