namespace Meridian.Messaging.Contracts;

/// <summary>Queue names. Kept in sync with <c>queues.json</c> by a contract test.</summary>
public static class QueueNames
{
    public const string ApprovalRequested = "approval-requested";
    public const string ApprovalDecided = "approval-decided";
    public const string ApprovalAudit = "approval-audit";

    public static IReadOnlyList<string> All { get; } = [ApprovalRequested, ApprovalDecided, ApprovalAudit];

    /// <summary>Poison queue convention: <c>&lt;queue&gt;-poison</c>, created by infra/queues.bicep.</summary>
    public static string PoisonOf(string queueName) => $"{queueName}-poison";
}
