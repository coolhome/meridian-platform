using System.Text.Json;
using Meridian.Bff.Clients;
using Meridian.ServiceDefaults.Authentication;

namespace Meridian.Bff.Endpoints;

internal static class ApiEndpoints
{
    public static IEndpointRouteBuilder MapApiEndpoints(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api").RequireAuthorization(MeridianPolicies.Requester);

        api.MapGet("/me", async (IIdentityClient identity, CancellationToken ct) =>
            await identity.GetMeAsync(ct) is { } me ? Results.Ok(me) : Results.Unauthorized());

        api.MapGet("/approvers", async (IIdentityClient identity, CancellationToken ct) => await identity.GetApproversAsync(ct));

        api.MapGet("/dashboard", async (DashboardService dashboard, CancellationToken ct) =>
            await dashboard.BuildAsync(ct) is { } d ? Results.Ok(d) : Results.Unauthorized());

        api.MapGet("/approvals", async (string? status, string? mine, bool? overdue, IApprovalsClient approvals, CancellationToken ct) =>
            await approvals.ListAsync(status, mine, overdue == true, ct));

        api.MapGet("/approvals/{id:guid}", async (Guid id, IApprovalsClient approvals, CancellationToken ct) =>
            (await approvals.GetAsync(id, ct)).ToHttpResult());

        api.MapPost("/approvals", async (JsonElement body, IApprovalsClient approvals, CancellationToken ct) =>
            (await approvals.CreateAsync(new JsonElementBody(body), ct)).ToHttpResult());

        api.MapPost("/approvals/{id:guid}/decision", async (Guid id, JsonElement body, IApprovalsClient approvals, CancellationToken ct) =>
                (await approvals.DecideAsync(id, new JsonElementBody(body), ct)).ToHttpResult())
            .RequireAuthorization(MeridianPolicies.Approver);

        return app;
    }
}
