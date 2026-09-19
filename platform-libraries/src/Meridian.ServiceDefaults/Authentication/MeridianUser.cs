using System.Security.Claims;

namespace Meridian.ServiceDefaults.Authentication;

public sealed record MeridianUser(string Id, string Name, IReadOnlyList<string> Roles)
{
    public bool IsInRole(string role) => Roles.Contains(role, StringComparer.OrdinalIgnoreCase);
}

public static class MeridianUserExtensions
{
    public static MeridianUser GetMeridianUser(this ClaimsPrincipal principal)
    {
        ArgumentNullException.ThrowIfNull(principal);
        var id = principal.FindFirstValue(ClaimTypes.NameIdentifier)
                 ?? principal.FindFirstValue("oid")
                 ?? principal.FindFirstValue("sub")
                 ?? throw new InvalidOperationException("Principal has no identifier claim.");
        var name = principal.FindFirstValue("preferred_username")
                   ?? principal.FindFirstValue(ClaimTypes.Name)
                   ?? principal.Identity?.Name
                   ?? id;
        var roles = principal.FindAll(ClaimTypes.Role).Select(c => c.Value).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        return new MeridianUser(id, name, roles);
    }
}
