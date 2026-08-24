using System.Runtime.CompilerServices;
using System.Threading.Channels;
using FreelanceApp.Application.Interfaces.Services;

[assembly: InternalsVisibleTo("FreelanceApp.Tests")]

namespace FreelanceApp.Infrastructure.Services;

// Singleton — ek hi channel poore app mein hai.
// Bounded(512): pressure pe purane items drop hote hain (DropOldest); OTP emails
// ke liye yahi theek hai — user dobara request kar sakta hai, guaranteed delivery
// ke liye outbox chahiye (docs/TODO.md).
public sealed class EmailQueueService : IEmailQueue
{
    private readonly Channel<EmailQueueItem> _channel =
        Channel.CreateBounded<EmailQueueItem>(new BoundedChannelOptions(512)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
            SingleWriter = false,
        });

    public void Enqueue(EmailQueueItem item) =>
        _channel.Writer.TryWrite(item); // in-memory write; kabhi block nahi karta

    // BackgroundService yahan se padh-ta hai — internal rakhna intentional hai
    // taake sirf EmailBackgroundService is channel ka reader bane.
    internal ChannelReader<EmailQueueItem> Reader => _channel.Reader;
}
