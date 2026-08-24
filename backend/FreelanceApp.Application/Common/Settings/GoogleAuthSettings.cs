namespace FreelanceApp.Application.Common.Settings;

public class GoogleAuthSettings
{
    public const string SectionName = "GoogleAuth";

    /// <summary>
    /// Accepted Google OAuth client IDs (the token's "aud"). Usually one per
    /// platform — Android, iOS, Web. A token whose audience isn't in this list
    /// is rejected, so only OUR apps' Google sign-ins are trusted.
    /// </summary>
    public string[] ClientIds { get; set; } = [];
}
