using FreelanceApp.Application.Exceptions;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace FreelanceApp.Api.ExceptionHandlers;

public class GlobalExceptionHandler(
    ILogger<GlobalExceptionHandler> logger,
    IHostEnvironment environment) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        // Log the exception
        logger.LogError(
            exception,
            "Unhandled exception occurred: {Message}",
            exception.Message);

        // Map exception to ProblemDetails
        var problemDetails = exception switch
        {
            AppException appEx => new ProblemDetails
            {
                Status = appEx.StatusCode,
                Title = GetTitleForStatus(appEx.StatusCode),
                Detail = appEx.Message,
                Type = $"https://httpstatuses.com/{appEx.StatusCode}"
            },
            _ => new ProblemDetails
            {
                Status = StatusCodes.Status500InternalServerError,
                Title = "Internal Server Error",
                Detail = environment.IsDevelopment()
                    ? exception.Message
                    : "An unexpected error occurred. Please try again later.",
                Type = "https://httpstatuses.com/500"
            }
        };

        // Add metadata
        problemDetails.Instance = httpContext.Request.Path;
        problemDetails.Extensions["traceId"] = Activity.Current?.Id
            ?? httpContext.TraceIdentifier;
        problemDetails.Extensions["timestamp"] = DateTime.UtcNow;

        // In Development: include stack trace for debugging
        if (environment.IsDevelopment() && exception is not AppException)
        {
            problemDetails.Extensions["stackTrace"] = exception.StackTrace;
        }

        // Set HTTP response
        httpContext.Response.StatusCode = problemDetails.Status ?? 500;
        httpContext.Response.ContentType = "application/problem+json";

        await httpContext.Response.WriteAsJsonAsync(
            problemDetails,
            cancellationToken);

        return true; // Exception handled
    }

    private static string GetTitleForStatus(int statusCode) => statusCode switch
    {
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        422 => "Unprocessable Entity",
        429 => "Too Many Requests",
        _ => "Error"
    };
}