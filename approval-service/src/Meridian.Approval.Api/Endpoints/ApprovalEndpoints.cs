using Meridian.Approval.Api.Application;
using Meridian.Approval.Api.Domain;
using Meridian.Messaging.Contracts.Events;
using Meridian.ServiceDefaults.Authentication;
using Meridian.ServiceDefaults.Middleware;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace Meridian.Approval.Api.Endpoints;

public sealed record CreateApprovalRequestBody(string Title, string? Description, IReadOnlyList<string> Approvers, DateTimeOffset? DueAt, int? RequiredApprovals);

public sealed record DecisionBody(ApprovalDecision Decision, string? Comment);

public sealed record DecisionResponse(string Approver, ApprovalDecision Decision, string? Comment, DateTimeOffset At);

public sealed record ApprovalResponse(
    Guid Id,
    string Title,
    string Description,
    string RequestedBy,
    IReadOnlyList<string> Approvers,
    int RequiredApprovals,
    ApprovalStatus Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? DueAt,
    DateTimeOffset? DecidedAt,
    bool Overdue,
    IReadOnlyList<DecisionResponse> Decisions)
{
    public static ApprovalResponse From(ApprovalRequest r, DateTimeOffset now) => new(
        r.Id, r.Title, r.Description, r.RequestedBy, r.Approvers, r.RequiredApprovals, r.Status, r.CreatedAt, r.DueAt, r.DecidedAt, r.IsOverdue(now),
        r.Decisions.Select(d => new DecisionResponse(d.Approver, d.Value, d.Comment, d.At)).ToArray());
}

internal static class ApprovalEndpoints
{
    public static IEndpointRouteBuilder MapApprovalEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/approvals").WithTags("Approvals");

        group.MapPost("/", async (CreateApprovalRequestBody body, ApprovalService service, HttpContext http, TimeProvider time, CancellationToken ct) =>
            {
                var created = await service.CreateAsync(
                    new CreateApprovalCommand(body.Title, body.Description, body.Approvers, body.DueAt, body.RequiredApprovals),
                    http.User.GetMeridianUser(),
                    http.GetCorrelationId(),
                    ct);
                return Results.Created($"/approvals/{created.Id}", ApprovalResponse.From(created, time.GetUtcNow()));
            })
            .RequireAuthorization(MeridianPolicies.Requester)
            .WithName("CreateApproval");

        group.MapGet("/", async ([FromQuery] ApprovalStatus? status, [FromQuery] string? mine, [FromQuery] bool? overdue, ApprovalService service, HttpContext http, TimeProvider time, CancellationToken ct) =>
            {
                var now = time.GetUtcNow();
                var items = await service.ListAsync(status, mine, overdue == true, http.User.GetMeridianUser(), ct);
                return items.Select(i => ApprovalResponse.From(i, now));
            })
            .RequireAuthorization(MeridianPolicies.Requester)
            .WithName("ListApprovals");

        group.MapGet("/{id:guid}", async (Guid id, ApprovalService service, TimeProvider time, CancellationToken ct) =>
            {
                var item = await service.GetAsync(id, ct);
                return item is null ? Results.NotFound() : Results.Ok(ApprovalResponse.From(item, time.GetUtcNow()));
            })
            .RequireAuthorization(MeridianPolicies.Requester)
            .WithName("GetApproval");

        group.MapPost("/{id:guid}/decision", async (Guid id, DecisionBody body, ApprovalService service, HttpContext http, TimeProvider time, CancellationToken ct) =>
            {
                var updated = await service.DecideAsync(id, new DecideCommand(body.Decision, body.Comment), http.User.GetMeridianUser(), http.GetCorrelationId(), ct);
                return Results.Ok(ApprovalResponse.From(updated, time.GetUtcNow()));
            })
            .RequireAuthorization(MeridianPolicies.Approver)
            .WithName("DecideApproval");

        return app;
    }
}

/// <summary>Maps <see cref="DomainException"/> to ProblemDetails (404 for not_found, 409 for state conflicts, 422 otherwise).</summary>
internal sealed class DomainExceptionHandler(IProblemDetailsService problemDetails) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        if (exception is not DomainException domain)
        {
            return false;
        }

        httpContext.Response.StatusCode = domain.Code switch
        {
            "not_found" => StatusCodes.Status404NotFound,
            "already_decided" or "duplicate_decision" or "conflict" => StatusCodes.Status409Conflict,
            "not_an_approver" or "self_approval" => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status422UnprocessableEntity,
        };

        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            Exception = exception,
            ProblemDetails = new ProblemDetails
            {
                Title = domain.Code,
                Detail = domain.Message,
                Status = httpContext.Response.StatusCode,
                Extensions = { ["correlationId"] = httpContext.GetCorrelationId() },
            },
        });
    }
}
