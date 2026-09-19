using Meridian.Approval.Api.Domain;
using Meridian.Messaging.Contracts.Events;
using Xunit;

namespace Meridian.Approval.Api.Tests;

public sealed class ApprovalRequestTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 19, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Requester_cannot_be_an_approver()
    {
        var ex = Assert.Throws<DomainException>(() => ApprovalRequest.Create("Laptop", "", "alice", ["alice", "bob"], Now));
        Assert.Equal("self_approval", ex.Code);
    }

    [Fact]
    public void Single_approval_completes_request_and_duplicates_are_rejected()
    {
        var request = ApprovalRequest.Create("Laptop", "M3", "alice", ["bob", "carol"], Now, Now.AddDays(2));

        Assert.True(request.Decide("bob", ApprovalDecision.Approved, "ok", Now.AddMinutes(1)));
        Assert.Equal(ApprovalStatus.Approved, request.Status);
        Assert.Equal("already_decided", Assert.Throws<DomainException>(() => request.Decide("carol", ApprovalDecision.Approved, null, Now)).Code);
    }

    [Fact]
    public void Two_required_approvals_need_two_distinct_approvers_and_one_rejection_rejects()
    {
        var request = ApprovalRequest.Create("Budget", "", "alice", ["bob", "carol", "dave"], Now, requiredApprovals: 2);

        Assert.False(request.Decide("bob", ApprovalDecision.Approved, null, Now));
        Assert.Equal(ApprovalStatus.Pending, request.Status);
        Assert.Equal("duplicate_decision", Assert.Throws<DomainException>(() => request.Decide("bob", ApprovalDecision.Approved, null, Now)).Code);
        Assert.Equal("not_an_approver", Assert.Throws<DomainException>(() => request.Decide("mallory", ApprovalDecision.Approved, null, Now)).Code);

        Assert.True(request.Decide("carol", ApprovalDecision.Rejected, "no budget", Now));
        Assert.Equal(ApprovalStatus.Rejected, request.Status);
        Assert.Equal(2, request.Decisions.Count);
    }

    [Fact]
    public void Overdue_only_while_pending()
    {
        var request = ApprovalRequest.Create("Laptop", "", "alice", ["bob"], Now, Now.AddHours(1));
        Assert.False(request.IsOverdue(Now));
        Assert.True(request.IsOverdue(Now.AddHours(2)));
        request.Decide("bob", ApprovalDecision.Approved, null, Now.AddHours(3));
        Assert.False(request.IsOverdue(Now.AddHours(4)));
    }
}
