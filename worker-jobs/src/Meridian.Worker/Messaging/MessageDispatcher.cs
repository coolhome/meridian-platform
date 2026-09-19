using System.Text.Json;
using Meridian.Messaging.Contracts;

namespace Meridian.Worker.Messaging;

/// <summary>Transport-neutral view of a dequeued message so the dispatch rules are unit-testable.</summary>
public sealed record IncomingMessage(string MessageId, string Body, long DequeueCount, DateTimeOffset? InsertedOn);

public enum DispatchOutcome
{
    Handled,
    Retry,
    Poison,
}

public sealed record DispatchResult(DispatchOutcome Outcome, string Reason, MessageHeader? Header = null);

public interface IMessageHandler<TPayload> where TPayload : IMeridianMessage
{
    Task HandleAsync(MessageEnvelope<TPayload> envelope, CancellationToken cancellationToken);
}

public sealed class MessagingOptions
{
    public const string SectionName = "Messaging";
    public string? QueueServiceUri { get; set; }
    public string? ConnectionString { get; set; }
    public int MaxDequeueCount { get; set; } = 5;
    public int BatchSize { get; set; } = 16;
    public int VisibilityTimeoutSeconds { get; set; } = 300;
    public int EmptyQueueDelaySeconds { get; set; } = 5;
}

/// <summary>
/// Applies the poison/retry rules and routes an envelope to the handler for <typeparamref name="TPayload"/>.
/// One dispatcher per queue; the queue carries exactly one message type.
/// </summary>
public sealed class MessageDispatcher<TPayload>(IMessageHandler<TPayload> handler, int maxDequeueCount, ILogger<MessageDispatcher<TPayload>> logger)
    where TPayload : IMeridianMessage
{
    public async Task<DispatchResult> DispatchAsync(IncomingMessage message, CancellationToken cancellationToken)
    {
        if (message.DequeueCount > maxDequeueCount)
        {
            return new DispatchResult(DispatchOutcome.Poison, $"dequeue count {message.DequeueCount} exceeds {maxDequeueCount}");
        }

        MessageHeader header;
        try
        {
            header = MessageSerializer.PeekHeader(message.Body);
        }
        catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return new DispatchResult(DispatchOutcome.Poison, $"unreadable envelope: {ex.Message}");
        }

        if (!string.Equals(header.MessageType, TPayload.MessageType, StringComparison.Ordinal))
        {
            return new DispatchResult(DispatchOutcome.Poison, $"unexpected messageType {header.MessageType}", header);
        }

        if (header.SchemaVersion != TPayload.SchemaVersion)
        {
            return new DispatchResult(DispatchOutcome.Poison, $"unsupported schemaVersion {header.SchemaVersion}", header);
        }

        try
        {
            var envelope = MessageSerializer.Deserialize<TPayload>(message.Body);
            await handler.HandleAsync(envelope, cancellationToken);
            return new DispatchResult(DispatchOutcome.Handled, "ok", header);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Handler for {MessageType} failed on message {MessageId} (attempt {Attempt})", header.MessageType, message.MessageId, message.DequeueCount);
            return new DispatchResult(DispatchOutcome.Retry, ex.Message, header);
        }
    }
}
