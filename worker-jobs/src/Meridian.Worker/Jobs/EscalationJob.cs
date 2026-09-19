using Meridian.Messaging.Contracts.Events;

namespace Meridian.Worker.Jobs;

public sealed class EscalationOptions
{
    public const string SectionName = "Escalation";
    public int IntervalMinutes { get; set; } = 15;
    public bool Enabled { get; set; } = true;
}

/// <summary>Periodically asks approval-service for overdue requests and nudges their approvers.</summary>
internal sealed class EscalationJob(
    IApprovalApiClient approvals,
    INotifier notifier,
    IAuditWriter audit,
    TimeProvider time,
    Microsoft.Extensions.Options.IOptions<EscalationOptions> options,
    ILogger<EscalationJob> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!options.Value.Enabled)
        {
            logger.LogInformation("Escalation job disabled");
            return;
        }

        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(Math.Max(1, options.Value.IntervalMinutes)), time);
        do
        {
            try
            {
                var overdue = await approvals.GetOverdueAsync(stoppingToken);
                foreach (var item in overdue)
                {
                    foreach (var approver in item.Approvers)
                    {
                        await notifier.NotifyAsync(approver, $"Overdue: {item.Title}", $"Requested by {item.RequestedBy}, due {item.DueAt:u}.", stoppingToken);
                    }

                    await audit.WriteAsync(new ApprovalAuditEntry(item.Id, "escalated", "worker-jobs", $"overdue since {item.DueAt:u}", time.GetUtcNow()), Guid.NewGuid().ToString("n"), stoppingToken);
                }

                logger.LogInformation("Escalation pass complete: {Count} overdue request(s)", overdue.Count);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Escalation pass failed; will retry next interval");
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}
