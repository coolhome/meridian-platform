using Azure.Storage.Queues;
using Meridian.Messaging.Contracts;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Meridian.Worker.Messaging;

/// <summary>Readiness: the queues this worker consumes exist and are reachable.</summary>
internal sealed class QueueHealthCheck(QueueServiceClient queueService) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            foreach (var name in new[] { QueueNames.ApprovalRequested, QueueNames.ApprovalDecided, QueueNames.ApprovalAudit })
            {
                if (!await queueService.GetQueueClient(name).ExistsAsync(cancellationToken))
                {
                    return HealthCheckResult.Unhealthy($"queue {name} does not exist");
                }
            }

            return HealthCheckResult.Healthy();
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("queue service unreachable", ex);
        }
    }
}
