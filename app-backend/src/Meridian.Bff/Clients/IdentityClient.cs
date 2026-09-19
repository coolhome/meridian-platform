using System.Net.Http.Json;

namespace Meridian.Bff.Clients;

public interface IIdentityClient
{
    Task<PrincipalDto?> GetMeAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<PrincipalDto>> GetApproversAsync(CancellationToken cancellationToken);
}

/// <summary>Typed client; caller context is forwarded by Meridian.ServiceDefaults' CallerContextForwardingHandler.</summary>
public sealed class IdentityClient(HttpClient http) : IIdentityClient
{
    public async Task<PrincipalDto?> GetMeAsync(CancellationToken cancellationToken)
    {
        using var response = await http.GetAsync(new Uri("me", UriKind.Relative), cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        return await response.Content.ReadFromJsonAsync<PrincipalDto>(Json.Web, cancellationToken);
    }

    public async Task<IReadOnlyList<PrincipalDto>> GetApproversAsync(CancellationToken cancellationToken)
        => await http.GetFromJsonAsync<PrincipalDto[]>(new Uri("approvers", UriKind.Relative), Json.Web, cancellationToken) ?? [];
}
