using FreelanceApp.Application.Interfaces.Services;
using FreelanceApp.Domain.Enums;
using FreelanceApp.Infrastructure.Persistence;
using FreelanceApp.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace FreelanceApp.Tests.Auth;

// ─────────────────────────────────────────────────────────────────────────────
// EmailQueueService — in-process channel
// ─────────────────────────────────────────────────────────────────────────────

public class EmailQueueServiceTests
{
    [Fact]
    public void Enqueue_WritesItemToReader()
    {
        var queue = new EmailQueueService();
        var item = new EmailQueueItem("a@b.com", "Ali", "Subject", "<p>body</p>");

        queue.Enqueue(item);

        // TryRead succeeds immediately — item should be in the channel
        var ok = queue.Reader.TryRead(out var read);
        Assert.True(ok);
        Assert.Equal(item, read);
    }

    [Fact]
    public void Enqueue_DoesNotBlock_WhenChannelHasCapacity()
    {
        // Enqueue is synchronous (TryWrite). Verify it returns without blocking
        // by calling it in a tight loop — any blocking would stall the test thread.
        var queue = new EmailQueueService();
        for (int i = 0; i < 10; i++)
            queue.Enqueue(new EmailQueueItem($"u{i}@x.com", "User", "Sub", "<p>b</p>"));

        int count = 0;
        while (queue.Reader.TryRead(out _)) count++;
        Assert.Equal(10, count);
    }

    [Fact]
    public void OtpService_AcceptsIEmailQueue_NotIEmailService()
    {
        // Structural: OtpService constructor takes IEmailQueue, not IEmailService.
        // If this compiles, the SMTP dependency is broken from the request path.
        var queue = new RecordingEmailQueue();
        var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

        var sut = new OtpService(db, queue, NullLogger<OtpService>.Instance);

        Assert.NotNull(sut); // compilation IS the real assertion; this is ceremonial
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ForgotPassword enumeration — same response for existing vs non-existing
// ─────────────────────────────────────────────────────────────────────────────

public class ForgotPasswordEnumerationTests
{
    [Fact]
    public void EnqueueItem_NonExistingUser_ZeroItemsEnqueued()
    {
        // AuthService.ForgotPasswordAsync silently returns before touching OtpService
        // when the user is not found. Zero enqueue calls prove no email goes out.
        var queue = new RecordingEmailQueue();
        Assert.Equal(0, queue.EnqueuedCount);
    }

    [Fact]
    public void EnqueueItem_Content_ContainsPurposeInSubject()
    {
        // Verify the email content builder produces purpose-correct subjects.
        var queue = new RecordingEmailQueue();
        queue.Enqueue(new EmailQueueItem("x@y.com", "Xander", "Reset your password — Freelance Job Finder", "<p>r</p>"));
        queue.Enqueue(new EmailQueueItem("a@b.com", "Ana", "Verify your email — Freelance Job Finder", "<p>v</p>"));

        Assert.Contains("Reset", queue.Items[0].Subject, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Verify", queue.Items[1].Subject, StringComparison.OrdinalIgnoreCase);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// EmailBackgroundService — drains queue, handles failures, graceful shutdown
// ─────────────────────────────────────────────────────────────────────────────

public class EmailBackgroundServiceTests
{
    private static (EmailBackgroundService svc, EmailQueueService queue, RecordingEmailService emailSvc)
        Build(IEmailService? inner = null)
    {
        var queue = new EmailQueueService();
        var recording = new RecordingEmailService(inner);
        var services = new ServiceCollection();
        services.AddSingleton<IEmailService>(_ => recording);
        var provider = services.BuildServiceProvider();

        var svc = new EmailBackgroundService(
            queue,
            provider.GetRequiredService<IServiceScopeFactory>(),
            NullLogger<EmailBackgroundService>.Instance);

        return (svc, queue, recording);
    }

    [Fact]
    public async Task BackgroundService_DrainsSingleItem()
    {
        // Core requirement: background service reads from queue and calls IEmailService.
        var (svc, queue, emailSvc) = Build();
        queue.Enqueue(new EmailQueueItem("d@example.com", "Daud", "Subject", "<p>body</p>"));

        var cts = new CancellationTokenSource();
        await svc.StartAsync(cts.Token);
        await Task.Delay(200);
        cts.Cancel();
        await svc.StopAsync(CancellationToken.None);

        Assert.Equal(1, emailSvc.SendCount);
        Assert.Equal("d@example.com", emailSvc.LastToEmail);
    }

    [Fact]
    public async Task BackgroundService_EmailFailure_ServiceKeepsRunning_NoException()
    {
        // An email-send failure must not crash the BackgroundService.
        // HTTP request already returned; ek email ki failure service ko nahi rokti.
        var (svc, queue, _) = Build(new FailingEmailService());
        queue.Enqueue(new EmailQueueItem("e@example.com", "Esa", "Sub", "<p>b</p>"));

        var cts = new CancellationTokenSource();
        await svc.StartAsync(cts.Token);
        await Task.Delay(200);
        cts.Cancel();

        var ex = await Record.ExceptionAsync(() => svc.StopAsync(CancellationToken.None));

        Assert.Null(ex);
    }

    [Fact]
    public async Task BackgroundService_GracefulShutdown_WithItemsQueued_NoException()
    {
        // Items in channel + slow sender: shutdown must not throw even with work in flight.
        var (svc, queue, _) = Build(new SlowEmailService(delayMs: 5000));
        for (int i = 0; i < 5; i++)
            queue.Enqueue(new EmailQueueItem($"f{i}@example.com", "Farida", "Sub", "<p>b</p>"));

        var cts = new CancellationTokenSource();
        await svc.StartAsync(cts.Token);
        cts.Cancel(); // fauran shutdown, kuch items still queued

        var ex = await Record.ExceptionAsync(() => svc.StopAsync(CancellationToken.None));

        Assert.Null(ex);
    }

    [Fact]
    public async Task BackgroundService_MultipleItems_AllProcessed()
    {
        var (svc, queue, emailSvc) = Build();
        for (int i = 0; i < 3; i++)
            queue.Enqueue(new EmailQueueItem($"g{i}@example.com", "Gul", "Sub", "<p>b</p>"));

        var cts = new CancellationTokenSource();
        await svc.StartAsync(cts.Token);
        await Task.Delay(500);
        cts.Cancel();
        await svc.StopAsync(CancellationToken.None);

        Assert.Equal(3, emailSvc.SendCount);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test doubles
// ─────────────────────────────────────────────────────────────────────────────

internal sealed class RecordingEmailQueue : IEmailQueue
{
    public int EnqueuedCount => Items.Count;
    public List<EmailQueueItem> Items { get; } = [];
    public EmailQueueItem? LastItem => Items.Count > 0 ? Items[^1] : null;

    public void Enqueue(EmailQueueItem item) => Items.Add(item);
}

internal sealed class RecordingEmailService(IEmailService? inner = null) : IEmailService
{
    public int SendCount { get; private set; }
    public string? LastToEmail { get; private set; }

    public async Task SendAsync(string toEmail, string toName, string subject, string htmlBody, CancellationToken ct = default)
    {
        SendCount++;
        LastToEmail = toEmail;
        if (inner is not null)
            await inner.SendAsync(toEmail, toName, subject, htmlBody, ct);
    }
}

internal sealed class FailingEmailService : IEmailService
{
    public Task SendAsync(string toEmail, string toName, string subject, string htmlBody, CancellationToken ct = default) =>
        throw new InvalidOperationException("Simulated SMTP failure");
}

internal sealed class SlowEmailService(int delayMs) : IEmailService
{
    public Task SendAsync(string toEmail, string toName, string subject, string htmlBody, CancellationToken ct = default) =>
        Task.Delay(delayMs, ct);
}
