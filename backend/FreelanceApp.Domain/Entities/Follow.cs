namespace FreelanceApp.Domain.Entities;

public class Follow
{
    public Guid Id { get; set; }
    public Guid FollowerId { get; set; }   // who is doing the following
    public Guid FolloweeId { get; set; }   // who is being followed
    public DateTime CreatedAt { get; set; }

    public User? Follower { get; set; }
    public User? Followee { get; set; }
}
