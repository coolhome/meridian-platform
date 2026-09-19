using System.Collections.Concurrent;
using Meridian.Approval.Api.Application;
using Meridian.Approval.Api.Domain;

namespace Meridian.Approval.Api.Infrastructure;

internal sealed class InMemoryApprovalRepository : IApprovalRepository
{
    private readonly ConcurrentDictionary<Guid, ApprovalDocument> _store = new();

    public Task<ApprovalRequest?> GetAsync(Guid id, CancellationToken cancellationToken)
        => Task.FromResult(_store.TryGetValue(id, out var doc) ? doc.ToDomain() : null);

    public Task<IReadOnlyList<ApprovalRequest>> ListAsync(ApprovalQuery query, CancellationToken cancellationToken)
    {
        IReadOnlyList<ApprovalRequest> result = _store.Values
            .Select(d => d.ToDomain())
            .Where(r => query.Status is null || r.Status == query.Status)
            .Where(r => query.RequestedBy is null || string.Equals(r.RequestedBy, query.RequestedBy, StringComparison.OrdinalIgnoreCase))
            .Where(r => query.Approver is null || r.Approvers.Contains(query.Approver, StringComparer.OrdinalIgnoreCase))
            .Where(r => !query.OverdueOnly || r.IsOverdue(query.Now))
            .OrderByDescending(r => r.CreatedAt)
            .ToArray();
        return Task.FromResult(result);
    }

    public Task AddAsync(ApprovalRequest request, CancellationToken cancellationToken)
    {
        if (!_store.TryAdd(request.Id, ApprovalDocument.From(request)))
        {
            throw new DomainException("conflict", $"Approval {request.Id} already exists.");
        }

        return Task.CompletedTask;
    }

    public Task UpdateAsync(ApprovalRequest request, CancellationToken cancellationToken)
    {
        _store[request.Id] = ApprovalDocument.From(request);
        return Task.CompletedTask;
    }
}
