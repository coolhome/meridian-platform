namespace Meridian.Messaging.Contracts;

/// <summary>Transport-agnostic envelope. Matches <c>schemas/envelope.schema.json</c>.</summary>
public sealed record MessageEnvelope<TPayload>(
    string MessageId,
    string MessageType,
    int SchemaVersion,
    DateTimeOffset OccurredAt,
    string CorrelationId,
    string Source,
    TPayload Payload)
    where TPayload : IMeridianMessage;

public static class MessageEnvelope
{
    public static MessageEnvelope<TPayload> Create<TPayload>(
        TPayload payload,
        string source,
        string? correlationId = null,
        TimeProvider? timeProvider = null)
        where TPayload : IMeridianMessage
    {
        ArgumentNullException.ThrowIfNull(payload);
        ArgumentException.ThrowIfNullOrWhiteSpace(source);

        return new MessageEnvelope<TPayload>(
            MessageId: Guid.NewGuid().ToString("n"),
            MessageType: TPayload.MessageType,
            SchemaVersion: TPayload.SchemaVersion,
            OccurredAt: (timeProvider ?? TimeProvider.System).GetUtcNow(),
            CorrelationId: string.IsNullOrWhiteSpace(correlationId) ? Guid.NewGuid().ToString("n") : correlationId,
            Source: source,
            Payload: payload);
    }
}
