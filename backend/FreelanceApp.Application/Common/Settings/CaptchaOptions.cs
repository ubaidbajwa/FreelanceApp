namespace FreelanceApp.Application.Common.Settings;

public class CaptchaOptions
{
    public const string SectionName = "Captcha";

    /// <summary>
    /// Master switch. Development default is <c>false</c> so local/emulator
    /// testing works without a live captcha — the verifier bypasses and logs a
    /// warning. Must be <c>true</c> in any environment that faces real traffic.
    /// </summary>
    public bool Enabled { get; set; } = false;

    /// <summary>reCAPTCHA v2 secret key (used with the siteverify endpoint). Secret — never commit.</summary>
    public string SecretKey { get; set; } = string.Empty;

    /// <summary>Public v2 (checkbox) site key issued to the frontend.</summary>
    public string SiteKey { get; set; } = string.Empty;

    /// <summary>siteverify endpoint. Overridable for tests / Enterprise routing.</summary>
    public string VerifyEndpoint { get; set; } = "https://www.google.com/recaptcha/api/siteverify";
}
