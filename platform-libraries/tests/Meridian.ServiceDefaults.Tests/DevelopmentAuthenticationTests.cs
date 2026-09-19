using System.Net;
using System.Net.Http.Json;
using Meridian.ServiceDefaults;
using Meridian.ServiceDefaults.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace Meridian.ServiceDefaults.Tests;

public sealed class DevelopmentAuthenticationTests
{
    private static async Task<HttpClient> CreateClientAsync(string environment = "Development")
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = environment });
        builder.WebHost.UseTestServer();
        builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Meridian:Auth:Mode"] = "Development",
        });
        builder.AddMeridianServiceDefaults("tests");
        var app = builder.Build();
        app.UseMeridianServiceDefaults();
        app.MapGet("/me", (HttpContext ctx) => ctx.User.GetMeridianUser());
        app.MapGet("/approve", () => Results.Ok()).RequireAuthorization(MeridianPolicies.Approver);
        await app.StartAsync();
        return app.GetTestClient();
    }

    [Fact]
    public async Task Health_is_anonymous_and_everything_else_requires_identity()
    {
        var client = await CreateClientAsync();
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync(new Uri("/health/live", UriKind.Relative))).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync(new Uri("/me", UriKind.Relative))).StatusCode);
    }

    [Fact]
    public async Task Development_headers_become_a_principal_with_roles()
    {
        var client = await CreateClientAsync();
        client.DefaultRequestHeaders.Add(DevelopmentAuthenticationHandler.UserHeader, "alice");
        client.DefaultRequestHeaders.Add(DevelopmentAuthenticationHandler.RolesHeader, "Approver");

        var me = await client.GetFromJsonAsync<MeridianUser>(new Uri("/me", UriKind.Relative));
        Assert.NotNull(me);
        Assert.Equal("alice", me.Name);
        Assert.True(me.IsInRole(MeridianRoles.Approver));
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync(new Uri("/approve", UriKind.Relative))).StatusCode);

        client.DefaultRequestHeaders.Remove(DevelopmentAuthenticationHandler.RolesHeader);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync(new Uri("/approve", UriKind.Relative))).StatusCode);
    }

    [Fact]
    public async Task Development_mode_is_rejected_outside_development()
    {
        await Assert.ThrowsAsync<InvalidOperationException>(() => CreateClientAsync(Environments.Production));
    }
}
