namespace Meridian.Messaging.Contracts.Events;

public enum ApprovalDecision
{
    Approved,
    Rejected,
}

/// <summary>Raised by approval-service when an approver records a decision. Schema: approval-decided.v1.</summary>
public sealed record ApprovalDecided(
    Guid ApprovalId,
    ApprovalDecision Decision,
    string DecidedBy,
    string? Comment,
    DateTimeOffset DecidedAt) : IMeridianMessage
{
    public static string MessageType => "meridian.approval.decided";
    public static int SchemaVersion => 1;
}
