namespace FreelanceApp.Domain.Enums;

// Controls who may send this user a connection request.
// null and Everyone are identical in semantics — existing users whose profile was created
// before this column existed are never blocked (same progressive-profiling reasoning as
// AvailabilityStatus: nullable means "user hasn't set a preference yet → open default").
//
// SCOPE NOTE: only "who can send connection requests" is implemented here because it maps
// to a real, enforceable action (the send-request endpoint). Page/event/newsletter/member
// invitation toggles deliberately omitted — those product surfaces don't exist yet, so
// adding them now would create fake controls that mislead users. Add each toggle when the
// corresponding feature ships.
public enum ConnectionInvitePolicy
{
    Everyone    = 0,
    MutualsOnly = 1,
    NoOne       = 2
}
