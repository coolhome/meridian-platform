using System.Net.Http.Json;
using Microsoft.AspNetCore.WebUtilities;

namespace Meridian.Bff.Clients;

public interface IApprovalsClient
{
    Task<IReadOnlyList<ApprovalSummaryDto>> ListAsync(string? status, string? mine, bool overdue, CancellationToken cancellationToken);

    Task<DownstreamResult> GetAsync(Guid id, CancellationToken cancellationToken);

    Task<DownstreamResult> CreateAsync(JsonElementBody body, CancellationToken cancellationToken);

    Task<DownstreamResult> DecideAsync(Guid id, JsonElementBody body, CancellationToken cancellationToken);
}

/// <summary>Raw JSON body forwarded as-is so the approval-service stays the single owner of the request contract.</summary>
public sealed record JsonElementBody(System.Text.Json.JsonElement Value);

public sealed class ApprovalsClient(HttpClient http) : IApprovalsClient
{
    public async Task<IReadOnlyList<ApprovalSummaryDto>> ListAsync(string? status, string? mine, bool overdue, CancellationToken cancellationToken)
    {
        var query = new Dictionary<string, string?>();
        if (!string.IsNullOrWhiteSpace(status))
        {
            query["status"] = status;
        }

        if (!string.IsNullOrWhiteSpace(mine))
        {
            query["mine"] = mine;
        }

        if (overdue)
        {
            query["overdue"] = "true";
        }

        var url = QueryHelpers.AddQueryString("approvals", query);
        return await http.GetFromJsonAsync<ApprovalSummaryDto[]>(new Uri(url, UriKind.Relative), Json.Web, cancellationToken) ?? [];
    }

    public async Task<DownstreamResult> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        using var response = await http.GetAsync(new Uri($"approvals/{id}", UriKind.Relative), cancellationToken);
        return await DownstreamResult.FromAsync(response, cancellationToken);
    }

    public async Task<DownstreamResult> CreateAsync(JsonElementBody body, CancellationToken cancellationToken)
    {
        using var response = await http.PostAsJsonAsync(new Uri("approvals", UriKind.Relative), body.Value, Json.Web, cancellationToken);
        return await DownstreamResult.FromAsync(response, cancellationToken);
    }

    public async Task<DownstreamResult> DecideAsync(Guid id, JsonElementBody body, CancellationToken cancellationToken)
    {
        using var response = await http.PostAsJsonAsync(new Uri($"approvals/{id}/decision", UriKind.Relative), body.Value, Json.Web, cancellationToken);
        return await DownstreamResult.FromAsync(response, cancellationToken);
    }
}
