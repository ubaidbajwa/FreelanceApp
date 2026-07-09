namespace FreelanceApp.Application.Interfaces.Services;

public interface IEmailService
{
    Task SendAsync(
        string toEmail,
        string toName,
        string subject,
        string htmlBody,
        CancellationToken ct = default);
}