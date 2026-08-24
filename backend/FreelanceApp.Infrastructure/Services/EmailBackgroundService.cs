using FreelanceApp.Application.Interfaces.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace FreelanceApp.Infrastructure.Services;

public sealed class EmailBackgroundService(
    EmailQueueService queue,
    IServiceScopeFactory scopeFactory,
    ILogger<EmailBackgroundService> logger) : BackgroundService
{
    // Per-email SMTP timeout. IEmailService async methods (ConnectAsync, AuthenticateAsync,
    // SendAsync) only respect CancellationToken — SmtpClient.Timeout is for sync ops only.
    // Is CancellationToken ke bina async SMTP calls indefinitely hang kar sakte hain.
    private const int SendTimeoutSeconds = 10;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var item in queue.Reader.ReadAllAsync(stoppingToken))
        {
            // Linked: stoppingToken (app shutdown) ya per-email timeout — jo pehle aaye.
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
            cts.CancelAfter(TimeSpan.FromSeconds(SendTimeoutSeconds));
            try
            {
                // IEmailService scoped hai, is liye scope per email banana zaroori hai.
                using var scope = scopeFactory.CreateScope();
                var emailService = scope.ServiceProvider.GetRequiredService<IEmailService>();
                await emailService.SendAsync(item.ToEmail, item.ToName, item.Subject, item.HtmlBody, cts.Token);
            }
            catch (OperationCanceledException) when (!stoppingToken.IsCancellationRequested)
            {
                // App shutdown nahi tha — yeh per-email timeout tha.
                logger.LogError(
                    "Email to {Email} timed out after {Timeout}s; message dropped. " +
                    "If persistent, check SMTP host connectivity.",
                    item.ToEmail, SendTimeoutSeconds);
            }
            catch (Exception ex)
            {
                // SMTP failure — log kar ke aage chalo; ek email ki failure service ko nahi rokti.
                logger.LogError(ex, "Email to {Email} | Subject: {Subject} — send failed; message dropped",
                    item.ToEmail, item.Subject);
            }
        }
        // stoppingToken cancelled → ReadAllAsync gracefully exits; items still in channel are
        // abandoned. Acceptable for OTP emails (user can request another).
        // Guaranteed delivery needs a DB outbox — see docs/TODO.md.
    }
}
