namespace FreelanceApp.Domain.Enums;

public enum ConversationStatus
{
    Pending = 0,    // Initiator ne shuru ki, doosre ne abhi respond nahi kiya
    Accepted = 1,   // Dono taraf messaging khuli hai
    Declined = 2    // Receiver ne request thukra di
}
