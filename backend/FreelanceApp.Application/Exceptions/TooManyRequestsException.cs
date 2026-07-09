namespace FreelanceApp.Application.Exceptions;

public class TooManyRequestsException : AppException
{
    public TooManyRequestsException(string message)
        : base(message, 429) // 429 is the standard status code for Too Many Requests
    {
    }
}