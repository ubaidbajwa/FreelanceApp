using FreelanceApp.Application.Features.Network.DTOs;

namespace FreelanceApp.Application.Features.Network.Models;

public sealed record SocialReachData(int Count, IReadOnlyList<SocialProofUser> Preview);
