namespace FreelanceApp.Application.Common.Settings;

public sealed class SuggestionSettings
{
    public const string SectionName = "Suggestions";

    public int MutualConnectionWeight { get; set; } = 10;
    public int SharedSkillWeight { get; set; } = 5;
    public int MaxCandidates { get; set; } = 500;
    public int CacheSeconds { get; set; } = 0;   // 0 = caching disabled

    // ── Follow-suggestion–specific ────────────────────────────────────────────
    public int SocialReachWeight { get; set; } = 15;
    public int MaxPopularityBonus { get; set; } = 10;
    public int TopPopularCandidates { get; set; } = 100;
}
