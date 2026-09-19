using Meridian.Identity.Api.Directory;
using Meridian.ServiceDefaults.Authentication;
using Microsoft.Extensions.Options;

namespace Meridian.Identity.Api.Endpoints;

public sealed record PrincipalResponse(string Id, string Name, IReadOnlyList<string> Roles, bool CanApprove);

public sealed record DiscoveryResponse(string AuthMode, IReadOnlyList<string> Roles, string Version);

internal static class IdentityEndpoints
{
    public static IEndpointRouteBuilder MapIdentityEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/.well-known/meridian-identity", (IOptions<MeridianAuthOptions> auth) =>
                new DiscoveryResponse(
                    auth.Value.Mode,
                    [MeridianRoles.Requester, MeridianRoles.Approver, MeridianRoles.Administrator, MeridianRoles.Service],
                    typeof(IdentityEndpoints).Assembly.GetName().Version?.ToString() ?? "0.0.0"))
            .AllowAnonymous()
            .WithName("Discovery");

        app.MapGet("/me", (HttpContext http) =>
            {
                var user = http.User.GetMeridianUser();
                return new PrincipalResponse(user.Id, user.Name, user.Roles, user.IsInRole(MeridianRoles.Approver) || user.IsInRole(MeridianRoles.Administrator));
            })
            .RequireAuthorization(MeridianPolicies.Requester)
            .WithName("Me");

        app.MapGet("/approvers", async (IDirectory directory, CancellationToken ct) =>
                (await directory.ListByRoleAsync(MeridianRoles.Approver, ct))
                    .Select(u => new PrincipalResponse(u.Id, u.Name, u.Roles, true)))
            .RequireAuthorization(MeridianPolicies.Requester)
            .WithName("Approvers");

        app.MapGet("/users/{id}", async (string id, IDirectory directory, CancellationToken ct) =>
            {
                var user = await directory.FindAsync(id, ct);
                return user is null
                    ? Results.NotFound()
                    : Results.Ok(new PrincipalResponse(user.Id, user.Name, user.Roles, user.Roles.Contains(MeridianRoles.Approver, StringComparer.OrdinalIgnoreCase)));
            })
            .RequireAuthorization(policy => policy.RequireRole(MeridianRoles.Approver, MeridianRoles.Administrator, MeridianRoles.Service))
            .WithName("UserById");

        return app;
    }
}
