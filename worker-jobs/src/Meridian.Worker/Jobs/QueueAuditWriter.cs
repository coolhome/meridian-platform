using Azure.Storage.Queues;
using Meridian.Messaging.Contracts;
using Meridian.Messaging.Contracts.Events;

namespace Meridian.Worker.Jobs;

internal sealed class QueueAuditWriter(QueueServiceClient queueService) : IAuditWriter
{
    private readonly QueueClient _queue = queueService.GetQueueClient(QueueNames.ApprovalAudit);

    private bool _ensured;

    public async Task WriteAsync(ApprovalAuditEntry entry, string correlationId, CancellationToken cancellationToken)
    {
        if (!_ensured)
        {
            await _queue.CreateIfNotExistsAsync(cancellationToken: cancellationToken);
            _ensured = true;
        }

        await _queue.SendMessageAsync(MessageSerializer.Serialize(MessageEnvelope.Create(entry, "worker-jobs", correlationId)), cancellationToken: cancellationToken);
    }
}
