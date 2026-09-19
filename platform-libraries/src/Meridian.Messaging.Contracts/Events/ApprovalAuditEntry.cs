namespace Meridian.Messaging.Contracts.Events;

/// <summary>Append-only audit record written by worker-jobs. Schema: approval-audit.v1.</summary>
public sealed record ApprovalAuditEntry(
    Guid ApprovalId,
    string Action,
    string Actor,
    string? Detail,
    DateTimeOffset At) : IMeridianMessage
{
    public static string MessageType => "meridian.approval.audit";
    public static int SchemaVersion => 1;
}
