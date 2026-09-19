using Azure.Storage.Queues;
using Azure.Storage.Queues.Models;
using Meridian.Messaging.Contracts;
using Microsoft.Extensions.Options;

namespace Meridian.Worker.Messaging;

/// <summary>Long-running receive loop for one queue. Poisoned messages are copied to &lt;queue&gt;-poison and deleted.</summary>
public sealed class QueueProcessor<TPayload>(
    QueueServiceClient queueService,
    MessageDispatcher<TPayload> dispatcher,
    IOptions<MessagingOptions> options,
    WorkerTelemetry telemetry,
    ILogger<QueueProcessor<TPayload>> logger,
    string queueName) : BackgroundService
    where TPayload : IMeridianMessage
{
    private readonly QueueClient _queue = queueService.GetQueueClient(queueName);
    private readonly QueueClient _poison = queueService.GetQueueClient(QueueNames.PoisonOf(queueName));

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var opts = options.Value;
        logger.LogInformation("Listening on {Queue} for {MessageType}", queueName, TPayload.MessageType);

        while (!stoppingToken.IsCancellationRequested)
        {
            QueueMessage[] batch;
            try
            {
                batch = (await _queue.ReceiveMessagesAsync(opts.BatchSize, TimeSpan.FromSeconds(opts.VisibilityTimeoutSeconds), stoppingToken)).Value;
                var props = await _queue.GetPropertiesAsync(stoppingToken);
                telemetry.RecordQueueLength(queueName, props.Value.ApproximateMessagesCount);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Receive from {Queue} failed; backing off", queueName);
                await Task.Delay(TimeSpan.FromSeconds(opts.EmptyQueueDelaySeconds * 2), stoppingToken);
                continue;
            }

            if (batch.Length == 0)
            {
                await Task.Delay(TimeSpan.FromSeconds(opts.EmptyQueueDelaySeconds), stoppingToken);
                continue;
            }

            foreach (var message in batch)
            {
                var incoming = new IncomingMessage(message.MessageId, message.Body.ToString(), message.DequeueCount, message.InsertedOn);
                var result = await dispatcher.DispatchAsync(incoming, stoppingToken);

                switch (result.Outcome)
                {
                    case DispatchOutcome.Handled:
                        await _queue.DeleteMessageAsync(message.MessageId, message.PopReceipt, stoppingToken);
                        telemetry.RecordHandled(queueName, result.Header, message.DequeueCount, message.InsertedOn);
                        break;
                    case DispatchOutcome.Poison:
                        logger.LogWarning("Poisoning message {MessageId} from {Queue}: {Reason}", message.MessageId, queueName, result.Reason);
                        await _poison.SendMessageAsync(message.Body, cancellationToken: stoppingToken);
                        await _queue.DeleteMessageAsync(message.MessageId, message.PopReceipt, stoppingToken);
                        telemetry.RecordPoisoned(queueName, result.Reason);
                        break;
                    case DispatchOutcome.Retry:
                        // Leave it; visibility timeout expiry re-queues it with DequeueCount + 1.
                        break;
                }
            }
        }
    }
}
