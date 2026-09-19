using Meridian.Approval.Api.Domain;
using Meridian.Messaging.Contracts.Events;
using Meridian.ServiceDefaults.Authentication;

namespace Meridian.Approval.Api.Application;

public sealed record CreateApprovalCommand(string Title, string? Description, IReadOnlyList<string> Approvers, DateTimeOffset? DueAt, int? RequiredApprovals);

public sealed record DecideCommand(ApprovalDecision Decision, string? Comment);

public sealed class ApprovalService(IApprovalRepository repository, IEventPublisher publisher, TimeProvider timeProvider, ILogger<ApprovalService> logger)
{
    public async Task<ApprovalRequest> CreateAsync(CreateApprovalCommand command, MeridianUser user, string correlationId, CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        var request = ApprovalRequest.Create(command.Title, command.Description ?? string.Empty, user.Name, command.Approvers, now, command.DueAt, command.RequiredApprovals ?? 1);
        await repository.AddAsync(request, cancellationToken);

        await publisher.PublishAsync(
            new ApprovalRequested(request.Id, request.Title, request.RequestedBy, request.Approvers, request.CreatedAt, request.DueAt),
            correlationId,
            cancellationToken);

        logger.LogInformation("Approval {ApprovalId} created by {RequestedBy} for {ApproverCount} approver(s)", request.Id, request.RequestedBy, request.Approvers.Count);
        return request;
    }

    public async Task<ApprovalRequest> DecideAsync(Guid id, DecideCommand command, MeridianUser user, string correlationId, CancellationToken cancellationToken)
    {
        var request = await repository.GetAsync(id, cancellationToken)
                      ?? throw new DomainException("not_found", $"Approval {id} does not exist.");

        var now = timeProvider.GetUtcNow();
        var final = request.Decide(user.Name, command.Decision, command.Comment, now);
        await repository.UpdateAsync(request, cancellationToken);

        await publisher.PublishAsync(
            new ApprovalDecided(request.Id, command.Decision, user.Name, command.Comment, now),
            correlationId,
            cancellationToken);

        logger.LogInformation("Approval {ApprovalId} {Decision} by {DecidedBy}; final={Final}", request.Id, command.Decision, user.Name, final);
        return request;
    }

    public Task<ApprovalRequest?> GetAsync(Guid id, CancellationToken cancellationToken) => repository.GetAsync(id, cancellationToken);

    public Task<IReadOnlyList<ApprovalRequest>> ListAsync(ApprovalStatus? status, string? mine, bool overdue, MeridianUser user, CancellationToken cancellationToken)
    {
        var query = new ApprovalQuery(
            status,
            RequestedBy: mine == "requested" ? user.Name : null,
            Approver: mine == "approving" ? user.Name : null,
            OverdueOnly: overdue,
            Now: timeProvider.GetUtcNow());
        return repository.ListAsync(query, cancellationToken);
    }
}
