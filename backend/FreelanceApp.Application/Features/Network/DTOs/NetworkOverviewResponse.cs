namespace FreelanceApp.Application.Features.Network.DTOs;

public sealed record NetworkOverviewResponse(
    int ConnectionsCount,
    int InvitesSentCount,
    int InvitesReceivedCount,
    int FollowingCount,
    int FollowersCount);
