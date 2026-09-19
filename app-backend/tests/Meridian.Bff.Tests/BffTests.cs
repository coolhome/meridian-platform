using System.Net;
using System.Net.Http.Json;
using Meridian.Bff.Clients;
using Meridian.Bff.Endpoints;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Meridian.Bff.Tests;

internal sealed class FakeIdentity(PrincipalDto? me) : IIdentityClient
{
    public Task<PrincipalDto?> GetMeAsync(CancellationToken cancellationToken) => Task.FromResult(me);
    public Task<IReadOnlyList<PrincipalDto>> GetApproversAsync(CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<PrincipalDto>>([]);
}

internal sealed class FakeApprovals(IReadOnlyList<ApprovalSummaryDto> requested, IReadOnlyList<ApprovalSummaryDto> approving) : IApprovalsClient
{
    public Task<IReadOnlyList<ApprovalSummaryDto>> ListAsync(string? status, string? mine, bool overdue, CancellationToken ct)
        => Task.FromResult(mine == "approving" ? approving : requested);
    public Task<DownstreamResult> GetAsync(Guid id, CancellationToken ct) => Task.FromResult(new DownstreamResult(404, "application/problem+json", "{}"));
    public Task<DownstreamResult> CreateAsync(JsonElementBody body, CancellationToken ct) => Task.FromResult(new DownstreamResult(201, "application/json", "{}"));
    public Task<DownstreamResult> DecideAsync(Guid id, JsonElementBody body, CancellationToken ct) => Task.FromResult(new DownstreamResult(409, "application/problem+json", "{\"title\":\"already_decided\"}"));
}

public sealed class DashboardServiceTests
{
    private static ApprovalSummaryDto Item(string status, bool overdue) => new(Guid.NewGuid(), "t", "alice", status, DateTimeOffset.UtcNow, null, overdue, ["bob"]);

    [Fact]
    public async Task Aggregates_counts_for_an_approver()
    {
        var service = new DashboardService(
            new FakeIdentity(new PrincipalDto("bob", "bob", ["Approver"], true)),
            new FakeApprovals(requested: [Item("Pending", true), Item("Approved", false)], approving: [Item("Pending", false), Item("Pending", true)]));

        var d = await service.BuildAsync(CancellationToken.None);

        Assert.NotNull(d);
        Assert.Equal(2, d.AwaitingMyDecision);
        Assert.Equal(1, d.MyOpenRequests);
        Assert.Equal(2, d.Overdue);
    }

    [Fact]
    public async Task Non_approvers_never_query_the_approving_view()
    {
        var service = new DashboardService(new FakeIdentity(new PrincipalDto("alice", "alice", [], false)), new FakeApprovals([], [Item("Pending", false)]));
        var d = await service.BuildAsync(CancellationToken.None);
        Assert.Equal(0, d!.AwaitingMyDecision);
    }
}

public sealed class BffEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public BffEndpointTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(b =>
        {
            b.UseEnvironment("Development");
            b.ConfigureServices(s =>
            {
                s.AddScoped<IIdentityClient>(_ => new FakeIdentity(new PrincipalDto("bob", "bob", ["Approver"], true)));
                s.AddScoped<IApprovalsClient>(_ => new FakeApprovals([], []));
            });
        });
    }

    [Fact]
    public async Task Requires_identity_and_passes_downstream_problem_through()
    {
        var anon = _factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anon.GetAsync(new Uri("/api/me", UriKind.Relative))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await anon.GetAsync(new Uri("/health/live", UriKind.Relative))).StatusCode);

        var bob = _factory.CreateClient();
        bob.DefaultRequestHeaders.Add("X-Meridian-User", "bob");
        bob.DefaultRequestHeaders.Add("X-Meridian-Roles", "Approver");
        var decide = await bob.PostAsJsonAsync(new Uri($"/api/approvals/{Guid.NewGuid()}/decision", UriKind.Relative), new { decision = "approved" });
        Assert.Equal(HttpStatusCode.Conflict, decide.StatusCode);
        Assert.Contains("already_decided", await decide.Content.ReadAsStringAsync());
    }
}
