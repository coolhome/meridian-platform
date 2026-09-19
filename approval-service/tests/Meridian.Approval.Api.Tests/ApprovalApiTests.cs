using System.Net;
using System.Net.Http.Json;
using Meridian.Approval.Api.Domain;
using Meridian.Approval.Api.Endpoints;
using Meridian.Messaging.Contracts.Events;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Meridian.Approval.Api.Tests;

public sealed class ApprovalApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public ApprovalApiTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(b => b.UseEnvironment("Development"));
    }

    private HttpClient As(string user, string? roles = null)
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Meridian-User", user);
        if (roles is not null)
        {
            client.DefaultRequestHeaders.Add("X-Meridian-Roles", roles);
        }

        return client;
    }

    [Fact]
    public async Task Create_then_approve_flow()
    {
        var alice = As("alice");
        var create = await alice.PostAsJsonAsync(new Uri("/approvals", UriKind.Relative), new CreateApprovalRequestBody("Laptop", "M3", ["bob"], null, null));
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var created = await create.Content.ReadFromJsonAsync<ApprovalResponse>();
        Assert.NotNull(created);
        Assert.Equal(ApprovalStatus.Pending, created.Status);

        // A requester without the Approver role is forbidden by policy before the domain is reached.
        var forbidden = await alice.PostAsJsonAsync(new Uri($"/approvals/{created.Id}/decision", UriKind.Relative), new DecisionBody(ApprovalDecision.Approved, null));
        Assert.Equal(HttpStatusCode.Forbidden, forbidden.StatusCode);

        var bob = As("bob", "Approver");
        var decide = await bob.PostAsJsonAsync(new Uri($"/approvals/{created.Id}/decision", UriKind.Relative), new DecisionBody(ApprovalDecision.Approved, "looks good"));
        Assert.Equal(HttpStatusCode.OK, decide.StatusCode);
        var decided = await decide.Content.ReadFromJsonAsync<ApprovalResponse>();
        Assert.Equal(ApprovalStatus.Approved, decided!.Status);
        Assert.Single(decided.Decisions);

        var again = await bob.PostAsJsonAsync(new Uri($"/approvals/{created.Id}/decision", UriKind.Relative), new DecisionBody(ApprovalDecision.Rejected, null));
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);

        var mine = await alice.GetFromJsonAsync<ApprovalResponse[]>(new Uri("/approvals?mine=requested", UriKind.Relative));
        Assert.Contains(mine!, a => a.Id == created.Id);
    }

    [Fact]
    public async Task Self_approval_is_rejected_at_creation()
    {
        var alice = As("alice");
        var create = await alice.PostAsJsonAsync(new Uri("/approvals", UriKind.Relative), new CreateApprovalRequestBody("Laptop", null, ["alice"], null, null));
        Assert.Equal(HttpStatusCode.Forbidden, create.StatusCode);
        var problem = await create.Content.ReadFromJsonAsync<Dictionary<string, object>>();
        Assert.Equal("self_approval", problem!["title"].ToString());
    }

    [Fact]
    public async Task Anonymous_is_unauthorized_but_health_is_open()
    {
        var anon = _factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anon.GetAsync(new Uri("/approvals", UriKind.Relative))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await anon.GetAsync(new Uri("/health/ready", UriKind.Relative))).StatusCode);
    }
}
