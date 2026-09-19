using System.Reflection;
using System.Text.Json;
using Meridian.Messaging.Contracts;
using Meridian.Messaging.Contracts.Events;
using Xunit;

namespace Meridian.Messaging.Contracts.Tests;

/// <summary>
/// The JSON Schemas are the contract. These tests fail when a C# payload drifts from its
/// schema (missing required property, wrong messageType/schemaVersion, unknown property).
/// </summary>
public sealed class SchemaContractTests
{
    public static TheoryData<Type, string> Payloads => new()
    {
        { typeof(ApprovalRequested), "approval-requested.v1.schema.json" },
        { typeof(ApprovalDecided), "approval-decided.v1.schema.json" },
        { typeof(ApprovalAuditEntry), "approval-audit.v1.schema.json" },
    };

    [Theory]
    [MemberData(nameof(Payloads))]
    public void Payload_matches_schema(Type payloadType, string schemaFile)
    {
        using var schema = JsonDocument.Parse(File.ReadAllText(Path.Combine("schemas", schemaFile)));
        var props = schema.RootElement.GetProperty("properties");

        var expectedType = props.GetProperty("messageType").GetProperty("const").GetString();
        var expectedVersion = props.GetProperty("schemaVersion").GetProperty("const").GetInt32();
        Assert.Equal(expectedType, StaticString(payloadType, nameof(IMeridianMessage.MessageType)));
        Assert.Equal(expectedVersion, StaticInt(payloadType, nameof(IMeridianMessage.SchemaVersion)));

        var payloadSchema = props.GetProperty("payload");
        var clrProps = payloadType.GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Select(p => JsonNamingPolicy.CamelCase.ConvertName(p.Name))
            .ToHashSet(StringComparer.Ordinal);

        foreach (var required in payloadSchema.GetProperty("required").EnumerateArray().Select(e => e.GetString()!))
        {
            Assert.Contains(required, clrProps);
        }

        var schemaProps = payloadSchema.GetProperty("properties").EnumerateObject().Select(p => p.Name).ToHashSet(StringComparer.Ordinal);
        Assert.Empty(clrProps.Except(schemaProps));
    }

    [Fact]
    public void Envelope_round_trips_and_header_is_peekable()
    {
        var payload = new ApprovalRequested(Guid.NewGuid(), "Laptop", "alice", ["bob"], DateTimeOffset.UtcNow, null);
        var envelope = MessageEnvelope.Create(payload, "approval-service", "corr-1");

        var json = MessageSerializer.Serialize(envelope);
        var header = MessageSerializer.PeekHeader(json);
        var back = MessageSerializer.Deserialize<ApprovalRequested>(json);

        Assert.Equal(ApprovalRequested.MessageType, header.MessageType);
        Assert.Equal(1, header.SchemaVersion);
        Assert.Equal("corr-1", header.CorrelationId);
        Assert.Equal(envelope.MessageId, back.MessageId);
        Assert.Equal(envelope.OccurredAt, back.OccurredAt);
        Assert.Equal(envelope.Source, back.Source);
        Assert.Equal(payload.ApprovalId, back.Payload.ApprovalId);
        Assert.Equal(payload.Title, back.Payload.Title);
        Assert.Equal(payload.Approvers, back.Payload.Approvers);
        Assert.Null(back.Payload.DueAt);
        Assert.Contains("\"decision\"", MessageSerializer.Serialize(MessageEnvelope.Create(new ApprovalDecided(Guid.NewGuid(), ApprovalDecision.Approved, "bob", null, DateTimeOffset.UtcNow), "t")));
        Assert.Contains("\"approved\"", MessageSerializer.Serialize(MessageEnvelope.Create(new ApprovalDecided(Guid.NewGuid(), ApprovalDecision.Approved, "bob", null, DateTimeOffset.UtcNow), "t")));
    }

    [Fact]
    public void QueueNames_match_queues_json()
    {
        using var doc = JsonDocument.Parse(File.ReadAllText("queues.json"));
        var fromJson = doc.RootElement.GetProperty("queues").EnumerateArray().Select(q => q.GetProperty("name").GetString()!).OrderBy(x => x).ToArray();
        Assert.Equal(fromJson, QueueNames.All.OrderBy(x => x).ToArray());
    }

    private static string? StaticString(Type t, string name) => (string?)t.GetProperty(name, BindingFlags.Public | BindingFlags.Static)!.GetValue(null);
    private static int StaticInt(Type t, string name) => (int)t.GetProperty(name, BindingFlags.Public | BindingFlags.Static)!.GetValue(null)!;
}
