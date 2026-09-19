using Azure.Storage.Queues;
using Meridian.Messaging.Contracts;
using Meridian.Messaging.Contracts.Events;

namespace Meridian.Worker.Jobs;

internal sealed class QueueAuditWriter(QueueServiceClient queueService) : IAuditWriter
{
    private readonly QueueClient _queue = queueService.GetQueueClient(QueueNames.ApprovalAudit);

    public Task WriteAsync(ApprovalAuditEntry entry, string correlationId, CancellationToken cancellationToken)
        => _queue.SendMessageAsync(MessageSerializer.Serialize(MessageEnvelope.Create(entry, "worker-jobs", correlationId)), cancellationToken: cancellationToken);
}
