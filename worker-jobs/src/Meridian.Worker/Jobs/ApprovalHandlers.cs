using Meridian.Messaging.Contracts;
using Meridian.Messaging.Contracts.Events;
using Meridian.Worker.Messaging;

namespace Meridian.Worker.Jobs;

public interface IAuditWriter
{
    Task WriteAsync(ApprovalAuditEntry entry, string correlationId, CancellationToken cancellationToken);
}

internal sealed class ApprovalRequestedHandler(INotifier notifier, IAuditWriter audit, TimeProvider time) : IMessageHandler<ApprovalRequested>
{
    public async Task HandleAsync(MessageEnvelope<ApprovalRequested> envelope, CancellationToken cancellationToken)
    {
        var p = envelope.Payload;
        foreach (var approver in p.Approvers)
        {
            await notifier.NotifyAsync(approver, $"Approval needed: {p.Title}", $"{p.RequestedBy} requested your approval{(p.DueAt is { } d ? $" by {d:u}" : string.Empty)}.", cancellationToken);
        }

        await audit.WriteAsync(new ApprovalAuditEntry(p.ApprovalId, "notified", "worker-jobs", $"{p.Approvers.Count} approver(s) notified", time.GetUtcNow()), envelope.CorrelationId, cancellationToken);
    }
}

internal sealed class ApprovalDecidedHandler(INotifier notifier, IAuditWriter audit, TimeProvider time) : IMessageHandler<ApprovalDecided>
{
    public async Task HandleAsync(MessageEnvelope<ApprovalDecided> envelope, CancellationToken cancellationToken)
    {
        var p = envelope.Payload;
        await notifier.NotifyAsync("requester-of:" + p.ApprovalId, $"Request {p.Decision}", $"{p.DecidedBy} {p.Decision.ToString().ToLowerInvariant()} your request. {p.Comment}".Trim(), cancellationToken);
        await audit.WriteAsync(new ApprovalAuditEntry(p.ApprovalId, p.Decision.ToString().ToLowerInvariant(), p.DecidedBy, p.Comment, time.GetUtcNow()), envelope.CorrelationId, cancellationToken);
    }
}
