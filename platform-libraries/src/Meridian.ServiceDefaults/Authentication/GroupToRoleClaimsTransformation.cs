using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace Meridian.ServiceDefaults.Authentication;

/// <summary>Maps Entra ID <c>groups</c> claims to platform roles using <see cref="MeridianAuthOptions.RoleMappings"/>.</summary>
internal sealed class GroupToRoleClaimsTransformation(IOptionsMonitor<MeridianAuthOptions> options) : IClaimsTransformation
{
    public Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
    {
        if (principal.Identity is not ClaimsIdentity identity || !identity.IsAuthenticated)
        {
            return Task.FromResult(principal);
        }

        var mappings = options.CurrentValue.RoleMappings;
        var existing = identity.FindAll(ClaimTypes.Role).Select(c => c.Value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var group in identity.FindAll("groups").Select(c => c.Value))
        {
            if (mappings.TryGetValue(group, out var role) && existing.Add(role))
            {
                identity.AddClaim(new Claim(ClaimTypes.Role, role));
            }
        }

        // Applications calling with client credentials carry app roles in "roles"; surface them as roles too.
        foreach (var appRole in identity.FindAll("roles").Select(c => c.Value))
        {
            if (existing.Add(appRole))
            {
                identity.AddClaim(new Claim(ClaimTypes.Role, appRole));
            }
        }

        return Task.FromResult(principal);
    }
}
