using System.Text.Json.Serialization;
using Meridian.Approval.Api.Domain;
using Meridian.Messaging.Contracts.Events;

namespace Meridian.Approval.Api.Infrastructure;

/// <summary>Persistence shape (Cosmos document / in-memory record). Keeps the aggregate free of serializer concerns.</summary>
public sealed class ApprovalDocument
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string RequestedBy { get; set; } = string.Empty;
    public List<string> Approvers { get; set; } = [];
    public int RequiredApprovals { get; set; } = 1;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? DueAt { get; set; }
    public DateTimeOffset? DecidedAt { get; set; }
    public string Status { get; set; } = nameof(ApprovalStatus.Pending);
    public List<DecisionDocument> Decisions { get; set; } = [];

    public sealed class DecisionDocument
    {
        public string Approver { get; set; } = string.Empty;
        public string Value { get; set; } = string.Empty;
        public string? Comment { get; set; }
        public DateTimeOffset At { get; set; }
    }

    public static ApprovalDocument From(ApprovalRequest r) => new()
    {
        Id = r.Id.ToString("D"),
        Title = r.Title,
        Description = r.Description,
        RequestedBy = r.RequestedBy,
        Approvers = [.. r.Approvers],
        RequiredApprovals = r.RequiredApprovals,
        CreatedAt = r.CreatedAt,
        DueAt = r.DueAt,
        DecidedAt = r.DecidedAt,
        Status = r.Status.ToString(),
        Decisions = r.Decisions.Select(d => new DecisionDocument { Approver = d.Approver, Value = d.Value.ToString(), Comment = d.Comment, At = d.At }).ToList(),
    };

    public ApprovalRequest ToDomain() => ApprovalRequest.Rehydrate(
        Guid.Parse(Id),
        Title,
        Description,
        RequestedBy,
        Approvers,
        RequiredApprovals,
        CreatedAt,
        DueAt,
        Enum.Parse<ApprovalStatus>(Status),
        DecidedAt,
        Decisions.Select(d => new Decision(d.Approver, Enum.Parse<ApprovalDecision>(d.Value), d.Comment, d.At)));
}
