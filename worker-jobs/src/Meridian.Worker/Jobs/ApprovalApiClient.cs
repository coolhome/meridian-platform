using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using Meridian.ServiceDefaults.Authentication;
using Microsoft.Extensions.Options;

namespace Meridian.Worker.Jobs;

public sealed record OverdueApproval(Guid Id, string Title, string RequestedBy, IReadOnlyList<string> Approvers, DateTimeOffset? DueAt);

public interface IApprovalApiClient
{
    Task<IReadOnlyList<OverdueApproval>> GetOverdueAsync(CancellationToken cancellationToken);
}

internal sealed class ApprovalApiClient(HttpClient http) : IApprovalApiClient
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public async Task<IReadOnlyList<OverdueApproval>> GetOverdueAsync(CancellationToken cancellationToken)
        => await http.GetFromJsonAsync<OverdueApproval[]>(new Uri("approvals?status=Pending&overdue=true", UriKind.Relative), Json, cancellationToken) ?? [];
}

public sealed class DownstreamAuthOptions
{
    public const string SectionName = "Downstream:Approvals";
    public string BaseAddress { get; set; } = string.Empty;
    public string Scope { get; set; } = "api://meridian-approvals/.default";
}

/// <summary>
/// Service-to-service credential: managed identity token in EntraId mode, development headers otherwise.
/// </summary>
internal sealed class WorkerCredentialHandler(IOptions<MeridianAuthOptions> auth, IOptions<DownstreamAuthOptions> downstream) : DelegatingHandler
{
    private readonly TokenCredential _credential = new DefaultAzureCredential();

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        if (string.Equals(auth.Value.Mode, AuthModes.Development, StringComparison.OrdinalIgnoreCase))
        {
            request.Headers.TryAddWithoutValidation(DevelopmentAuthenticationHandler.UserHeader, "worker-jobs");
            request.Headers.TryAddWithoutValidation(DevelopmentAuthenticationHandler.RolesHeader, MeridianRoles.Service);
        }
        else
        {
            var token = await _credential.GetTokenAsync(new TokenRequestContext([downstream.Value.Scope]), cancellationToken);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        }

        return await base.SendAsync(request, cancellationToken);
    }
}
