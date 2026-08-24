namespace FreelanceApp.Application.Interfaces.Services;

public sealed record EmailQueueItem(string ToEmail, string ToName, string Subject, string HtmlBody);

// HTTP request path sirf yahan tak aata hai — SMTP ka wait request thread pe nahi hota.
// Enqueue kabhi block nahi karta; channel bounded hai aur DropOldest policy hai.
public interface IEmailQueue
{
    void Enqueue(EmailQueueItem item);
}
