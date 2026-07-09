namespace FreelanceApp.Application.Common.Settings;

public class AwsRekognitionSettings
{
    public const string SectionName = "AwsRekognition";

    public string AccessKeyId { get; set; } = string.Empty;
    public string SecretAccessKey { get; set; } = string.Empty;
    public string Region { get; set; } = "us-east-1";

    public double AutoVerifyThreshold { get; set; } = 80.0;    // ≥80% auto-verified
    public double ManualReviewThreshold { get; set; } = 60.0;  // 60-79% admin review
}