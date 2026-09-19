using System.Net;
using System.Net.Http.Json;
using Meridian.Identity.Api.Endpoints;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Meridian.Identity.Api.Tests;

public sealed class IdentityEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    public IdentityEndpointTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(b => b.UseEnvironment("Development"));
    }

    [Fact]
    public async Task Discovery_is_anonymous()
    {
        var client = _factory.CreateClient();
        var doc = await client.GetFromJsonAsync<DiscoveryResponse>(new Uri("/.well-known/meridian-identity", UriKind.Relative));
        Assert.NotNull(doc);
        Assert.Equal("Development", doc.AuthMode);
        Assert.Contains("Approver", doc.Roles);
    }

    [Fact]
    public async Task Me_reflects_headers_and_approver_flag()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Meridian-User", "bob");
        client.DefaultRequestHeaders.Add("X-Meridian-Roles", "Requester,Approver");

        var me = await client.GetFromJsonAsync<PrincipalResponse>(new Uri("/me", UriKind.Relative));
        Assert.NotNull(me);
        Assert.Equal("bob", me.Name);
        Assert.True(me.CanApprove);
    }

    [Fact]
    public async Task Approvers_come_from_directory_and_users_endpoint_is_role_gated()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Meridian-User", "alice");

        var approvers = await client.GetFromJsonAsync<PrincipalResponse[]>(new Uri("/approvers", UriKind.Relative));
        Assert.NotNull(approvers);
        Assert.Equal(["bob", "carol"], approvers.Select(a => a.Name).ToArray());

        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync(new Uri("/users/bob", UriKind.Relative))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await _factory.CreateClient().GetAsync(new Uri("/me", UriKind.Relative))).StatusCode);
    }
}
