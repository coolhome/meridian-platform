using Meridian.Messaging.Contracts.Events;

namespace Meridian.Approval.Api.Domain;

public enum ApprovalStatus
{
    Pending,
    Approved,
    Rejected,
}

public sealed record Decision(string Approver, ApprovalDecision Value, string? Comment, DateTimeOffset At);

/// <summary>Thrown when a command violates an aggregate invariant. Mapped to HTTP 409/422 by the API.</summary>
public sealed class DomainException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

/// <summary>The approval aggregate. All state changes go through <see cref="Create"/> and <see cref="Decide"/>.</summary>
public sealed class ApprovalRequest
{
    private readonly List<Decision> _decisions = [];

    private ApprovalRequest(Guid id, string title, string description, string requestedBy, IReadOnlyList<string> approvers, int requiredApprovals, DateTimeOffset createdAt, DateTimeOffset? dueAt)
    {
        Id = id;
        Title = title;
        Description = description;
        RequestedBy = requestedBy;
        Approvers = approvers;
        RequiredApprovals = requiredApprovals;
        CreatedAt = createdAt;
        DueAt = dueAt;
    }

    public Guid Id { get; }
    public string Title { get; }
    public string Description { get; }
    public string RequestedBy { get; }
    public IReadOnlyList<string> Approvers { get; }
    public int RequiredApprovals { get; }
    public DateTimeOffset CreatedAt { get; }
    public DateTimeOffset? DueAt { get; }
    public DateTimeOffset? DecidedAt { get; private set; }
    public ApprovalStatus Status { get; private set; } = ApprovalStatus.Pending;
    public IReadOnlyList<Decision> Decisions => _decisions;

    public static ApprovalRequest Create(string title, string description, string requestedBy, IEnumerable<string> approvers, DateTimeOffset now, DateTimeOffset? dueAt = null, int requiredApprovals = 1)
    {
        if (string.IsNullOrWhiteSpace(title) || title.Length > 200)
        {
            throw new DomainException("title_invalid", "Title is required and must be at most 200 characters.");
        }

        if (string.IsNullOrWhiteSpace(requestedBy))
        {
            throw new DomainException("requester_required", "Requester is required.");
        }

        var distinct = (approvers ?? [])
            .Where(a => !string.IsNullOrWhiteSpace(a))
            .Select(a => a.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        if (distinct.Length == 0)
        {
            throw new DomainException("approvers_required", "At least one approver is required.");
        }

        if (distinct.Contains(requestedBy, StringComparer.OrdinalIgnoreCase))
        {
            throw new DomainException("self_approval", "The requester cannot be one of the approvers.");
        }

        if (requiredApprovals < 1 || requiredApprovals > distinct.Length)
        {
            throw new DomainException("required_approvals_invalid", $"RequiredApprovals must be between 1 and {distinct.Length}.");
        }

        if (dueAt is not null && dueAt <= now)
        {
            throw new DomainException("due_in_past", "DueAt must be in the future.");
        }

        return new ApprovalRequest(Guid.NewGuid(), title.Trim(), description?.Trim() ?? string.Empty, requestedBy, distinct, requiredApprovals, now, dueAt);
    }

    /// <summary>Rehydration from persistence; performs no validation.</summary>
    internal static ApprovalRequest Rehydrate(Guid id, string title, string description, string requestedBy, IReadOnlyList<string> approvers, int requiredApprovals, DateTimeOffset createdAt, DateTimeOffset? dueAt, ApprovalStatus status, DateTimeOffset? decidedAt, IEnumerable<Decision> decisions)
    {
        var request = new ApprovalRequest(id, title, description, requestedBy, approvers, requiredApprovals, createdAt, dueAt)
        {
            Status = status,
            DecidedAt = decidedAt,
        };
        request._decisions.AddRange(decisions);
        return request;
    }

    /// <summary>Records a decision. Returns true when the request reached a final state with this decision.</summary>
    public bool Decide(string approver, ApprovalDecision decision, string? comment, DateTimeOffset now)
    {
        if (Status != ApprovalStatus.Pending)
        {
            throw new DomainException("already_decided", $"Request is already {Status}.");
        }

        if (string.Equals(approver, RequestedBy, StringComparison.OrdinalIgnoreCase))
        {
            throw new DomainException("self_approval", "The requester cannot decide their own request.");
        }

        if (!Approvers.Contains(approver, StringComparer.OrdinalIgnoreCase))
        {
            throw new DomainException("not_an_approver", $"{approver} is not an approver on this request.");
        }

        if (_decisions.Any(d => string.Equals(d.Approver, approver, StringComparison.OrdinalIgnoreCase)))
        {
            throw new DomainException("duplicate_decision", $"{approver} has already decided.");
        }

        if (comment is { Length: > 2000 })
        {
            throw new DomainException("comment_too_long", "Comment must be at most 2000 characters.");
        }

        _decisions.Add(new Decision(approver, decision, string.IsNullOrWhiteSpace(comment) ? null : comment.Trim(), now));

        if (decision == ApprovalDecision.Rejected)
        {
            Status = ApprovalStatus.Rejected;
            DecidedAt = now;
            return true;
        }

        if (_decisions.Count(d => d.Value == ApprovalDecision.Approved) >= RequiredApprovals)
        {
            Status = ApprovalStatus.Approved;
            DecidedAt = now;
            return true;
        }

        return false;
    }

    public bool IsOverdue(DateTimeOffset now) => Status == ApprovalStatus.Pending && DueAt is not null && DueAt < now;
}
