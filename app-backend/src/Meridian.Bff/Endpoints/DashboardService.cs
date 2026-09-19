using Meridian.Bff.Clients;

namespace Meridian.Bff.Endpoints;

public sealed record DashboardResponse(
    PrincipalDto Me,
    int AwaitingMyDecision,
    int MyOpenRequests,
    int Overdue,
    IReadOnlyList<ApprovalSummaryDto> ToApprove,
    IReadOnlyList<ApprovalSummaryDto> Requested);

public sealed class DashboardService(IIdentityClient identity, IApprovalsClient approvals)
{
    public async Task<DashboardResponse?> BuildAsync(CancellationToken cancellationToken)
    {
        var me = await identity.GetMeAsync(cancellationToken);
        if (me is null)
        {
            return null;
        }

        var requestedTask = approvals.ListAsync(null, "requested", false, cancellationToken);
        var toApproveTask = me.CanApprove
            ? approvals.ListAsync("Pending", "approving", false, cancellationToken)
            : Task.FromResult<IReadOnlyList<ApprovalSummaryDto>>([]);
        await Task.WhenAll(requestedTask, toApproveTask);

        var requested = await requestedTask;
        var toApprove = await toApproveTask;

        return new DashboardResponse(
            me,
            AwaitingMyDecision: toApprove.Count,
            MyOpenRequests: requested.Count(r => r.Status == "Pending"),
            Overdue: toApprove.Count(r => r.Overdue) + requested.Count(r => r.Overdue),
            ToApprove: toApprove,
            Requested: requested);
    }
}
