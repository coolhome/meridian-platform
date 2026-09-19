namespace Meridian.Worker.Jobs;

public interface INotifier
{
    Task NotifyAsync(string recipient, string subject, string body, CancellationToken cancellationToken);
}

/// <summary>Logs instead of sending. The mail/Teams implementation replaces this behind the same interface.</summary>
internal sealed class LogNotifier(ILogger<LogNotifier> logger) : INotifier
{
    public Task NotifyAsync(string recipient, string subject, string body, CancellationToken cancellationToken)
    {
        logger.LogInformation("Notify {Recipient}: {Subject} - {Body}", recipient, subject, body);
        return Task.CompletedTask;
    }
}
