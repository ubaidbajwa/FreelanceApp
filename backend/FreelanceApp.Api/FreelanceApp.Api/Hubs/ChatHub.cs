using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace FreelanceApp.Api.Hubs;

[Authorize]
public class ChatHub : Hub
{
    // M1: no client-to-server methods.
    // All writes go through REST so they reuse FluentValidation +
    // GlobalExceptionHandler. The hub is fan-out only.
}
