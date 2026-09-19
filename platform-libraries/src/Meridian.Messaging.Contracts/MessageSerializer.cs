using System.Text.Json;
using System.Text.Json.Serialization;

namespace Meridian.Messaging.Contracts;

/// <summary>
/// One serializer configuration for producers and consumers so wire format never depends on
/// a service's local JSON defaults.
/// </summary>
public static class MessageSerializer
{
    public static JsonSerializerOptions Options { get; } = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = false,
    };

    public static string Serialize<TPayload>(MessageEnvelope<TPayload> envelope)
        where TPayload : IMeridianMessage
        => JsonSerializer.Serialize(envelope, Options);

    public static MessageEnvelope<TPayload> Deserialize<TPayload>(string json)
        where TPayload : IMeridianMessage
        => JsonSerializer.Deserialize<MessageEnvelope<TPayload>>(json, Options)
           ?? throw new JsonException("Envelope deserialized to null.");

    /// <summary>Reads only the routing header so a consumer can dispatch before choosing a payload type.</summary>
    public static MessageHeader PeekHeader(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        return new MessageHeader(
            root.GetProperty("messageId").GetString() ?? string.Empty,
            root.GetProperty("messageType").GetString() ?? string.Empty,
            root.GetProperty("schemaVersion").GetInt32(),
            root.TryGetProperty("correlationId", out var c) ? c.GetString() ?? string.Empty : string.Empty);
    }
}

public sealed record MessageHeader(string MessageId, string MessageType, int SchemaVersion, string CorrelationId);
