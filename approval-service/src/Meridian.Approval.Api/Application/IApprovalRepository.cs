using Meridian.Approval.Api.Domain;

namespace Meridian.Approval.Api.Application;

public sealed record ApprovalQuery(ApprovalStatus? Status, string? RequestedBy, string? Approver, bool OverdueOnly, DateTimeOffset Now);

public interface IApprovalRepository
{
    Task<ApprovalRequest?> GetAsync(Guid id, CancellationToken cancellationToken);

    Task<IReadOnlyList<ApprovalRequest>> ListAsync(ApprovalQuery query, CancellationToken cancellationToken);

    Task AddAsync(ApprovalRequest request, CancellationToken cancellationToken);

    Task UpdateAsync(ApprovalRequest request, CancellationToken cancellationToken);
}
