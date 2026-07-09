using FreelanceApp.Application.Features.Kyc.DTOs;
using FreelanceApp.Application.Interfaces.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace FreelanceApp.Api.Controllers;

[ApiController]
[Route("api/admin/kyc")]
[Authorize(Policy = "AdminOnly")]
public class AdminKycController(IAdminKycService adminKycService) : ControllerBase
{
    [HttpGet("pending")]
    public async Task<IActionResult> GetPendingCases()
    {
        var cases = await adminKycService.GetPendingCasesAsync();
        return Ok(new { count = cases.Count, cases });
    }

    [HttpPost("{verificationId:guid}/approve")]
    public async Task<IActionResult> Approve(Guid verificationId)
    {
        await adminKycService.ApproveAsync(verificationId);
        return Ok(new { message = "KYC approved. User identity is now verified." });
    }

    [HttpPost("{verificationId:guid}/reject")]
    public async Task<IActionResult> Reject(
        Guid verificationId,
        [FromBody] AdminKycRejectRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Reason))
            return BadRequest(new { message = "Rejection reason is required." });

        await adminKycService.RejectAsync(verificationId, request.Reason.Trim());
        return Ok(new { message = "KYC rejected. User can resubmit if attempts remain." });
    }
}
