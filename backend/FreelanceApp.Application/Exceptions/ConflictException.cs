namespace FreelanceApp.Application.Exceptions;

public class ConflictException : AppException
{
    public ConflictException(string message)
        : base(message, 409)
    {
    }
}



public class ValidationException : AppException
{
    public ValidationException(string message)
        : base(message, 400)
    {
    }
}