namespace Meridian.Messaging.Contracts.Events;

/// <summary>Raised by approval-service when a request is created. Schema: approval-requested.v1.</summary>
public sealed record ApprovalRequested(
    Guid ApprovalId,
    string Title,
    string RequestedBy,
    IReadOnlyList<string> Approvers,
    DateTimeOffset RequestedAt,
    DateTimeOffset? DueAt) : IMeridianMessage
{
    public static string MessageType => "meridian.approval.requested";
    public static int SchemaVersion => 1;
}
