namespace Meridian.Messaging.Contracts;

/// <summary>
/// Implemented by every message payload. The static members feed the envelope header so a
/// consumer can route on <c>messageType</c> and <c>schemaVersion</c> before deserializing the payload.
/// </summary>
public interface IMeridianMessage
{
    /// <summary>Stable, namespaced type name, e.g. <c>meridian.approval.requested</c>.</summary>
    static abstract string MessageType { get; }

    /// <summary>Schema version of the payload. Bump on breaking change and publish a new schema file.</summary>
    static abstract int SchemaVersion { get; }
}
