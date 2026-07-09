using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.Mvc;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/test")]
public class TestController : ControllerBase
{
    private readonly IEmailService _emailService;

    public TestController(IEmailService emailService)
    {
        _emailService = emailService;
    }

    [HttpPost("send-email")]
    public async Task<IActionResult> SendTestEmail(
        [FromBody] TestEmailRequest request,
        CancellationToken ct)
    {
        var htmlBody = $@"
            <h2>Hello {request.ToName}!</h2>
            <p>This is a test email from <b>Freelance Job Finder App</b>.</p>
            <p>If you see this, Mailtrap is working perfectly! 🎉</p>
            <hr>
            <small>Sent at: {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC</small>
        ";

        await _emailService.SendAsync(
            toEmail: request.ToEmail,
            toName: request.ToName,
            subject: "Test Email — Freelance App",
            htmlBody: htmlBody,
            ct: ct);

        return Ok(new { message = "Email sent! Check Mailtrap inbox." });
    }
}

public record TestEmailRequest(string ToEmail, string ToName);