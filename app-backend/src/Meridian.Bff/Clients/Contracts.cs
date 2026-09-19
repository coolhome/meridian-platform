using System.Text.Json;

namespace Meridian.Bff.Clients;

// Wire shapes of the downstream services. Kept as loose JSON where the BFF only forwards.
public sealed record PrincipalDto(string Id, string Name, IReadOnlyList<string> Roles, bool CanApprove);

public sealed record ApprovalSummaryDto(Guid Id, string Title, string RequestedBy, string Status, DateTimeOffset CreatedAt, DateTimeOffset? DueAt, bool Overdue, IReadOnlyList<string> Approvers);

/// <summary>A downstream response passed through unchanged (status + body), used for POSTs and detail reads.</summary>
public sealed record DownstreamResult(int StatusCode, string? ContentType, string Body)
{
    public bool IsSuccess => StatusCode is >= 200 and < 300;

    public static async Task<DownstreamResult> FromAsync(HttpResponseMessage response, CancellationToken cancellationToken)
        => new((int)response.StatusCode, response.Content.Headers.ContentType?.ToString(), await response.Content.ReadAsStringAsync(cancellationToken));

    public IResult ToHttpResult() => Results.Content(Body, ContentType ?? "application/json", statusCode: StatusCode);
}

internal static class Json
{
    public static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);
}
