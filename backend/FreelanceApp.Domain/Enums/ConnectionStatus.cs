namespace FreelanceApp.Domain.Enums;

public enum ConnectionStatus
{
    Pending = 0,    // Request sent, receiver has not responded yet
    Accepted = 1,   // Both users are connected
    Rejected = 2    // Receiver declined the request
}
