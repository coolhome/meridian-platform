using System.Collections.Concurrent;
using Azure.Storage.Queues;
using Meridian.Approval.Api.Application;
using Meridian.Messaging.Contracts;
using Meridian.Messaging.Contracts.Events;
using Microsoft.ApplicationInsights;

namespace Meridian.Approval.Api.Infrastructure;

public sealed class MessagingOptions
{
    public const string SectionName = "Messaging";

    /// <summary>None | StorageQueue</summary>
    public string Provider { get; set; } = "None";

    /// <summary>https://{account}.queue.core.windows.net (managed identity). Preferred.</summary>
    public string? QueueServiceUri { get; set; }

    /// <summary>Local only (Azurite: UseDevelopmentStorage=true).</summary>
    public string? ConnectionString { get; set; }
}

/// <summary>Routes each payload type to its queue (queues.json is the source of truth via QueueNames).</summary>
internal static class QueueRouting
{
    public static string QueueFor<TPayload>() where TPayload : IMeridianMessage => typeof(TPayload) switch
    {
        var t when t == typeof(ApprovalRequested) => QueueNames.ApprovalRequested,
        var t when t == typeof(ApprovalDecided) => QueueNames.ApprovalDecided,
        var t when t == typeof(ApprovalAuditEntry) => QueueNames.ApprovalAudit,
        var t => throw new InvalidOperationException($"No queue mapped for {t.Name}."),
    };
}

internal sealed class StorageQueueEventPublisher(QueueServiceClient queueService, TelemetryClient telemetry, ILogger<StorageQueueEventPublisher> logger) : IEventPublisher
{
    private readonly ConcurrentDictionary<string, QueueClient> _clients = new();

    public async Task PublishAsync<TPayload>(TPayload payload, string correlationId, CancellationToken cancellationToken)
        where TPayload : IMeridianMessage
    {
        var queueName = QueueRouting.QueueFor<TPayload>();
        var client = _clients.GetOrAdd(queueName, n => queueService.GetQueueClient(n));
        var envelope = MessageEnvelope.Create(payload, "approval-service", correlationId);
        var body = MessageSerializer.Serialize(envelope);

        await client.SendMessageAsync(body, cancellationToken: cancellationToken);

        telemetry.TrackEvent("EventPublished", new Dictionary<string, string>
        {
            ["messageType"] = envelope.MessageType,
            ["messageId"] = envelope.MessageId,
            ["queue"] = queueName,
            ["correlationId"] = correlationId,
        });
        logger.LogInformation("Published {MessageType} {MessageId} to {Queue}", envelope.MessageType, envelope.MessageId, queueName);
    }
}

internal sealed class NullEventPublisher(ILogger<NullEventPublisher> logger) : IEventPublisher
{
    public Task PublishAsync<TPayload>(TPayload payload, string correlationId, CancellationToken cancellationToken)
        where TPayload : IMeridianMessage
    {
        logger.LogWarning("Messaging:Provider=None; dropped {MessageType} (correlation {CorrelationId})", TPayload.MessageType, correlationId);
        return Task.CompletedTask;
    }
}
