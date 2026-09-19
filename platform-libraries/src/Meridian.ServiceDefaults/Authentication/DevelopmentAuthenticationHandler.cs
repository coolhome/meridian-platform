using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Meridian.ServiceDefaults.Authentication;

/// <summary>
/// Header-based identity for local development only (guarded by environment check in
/// <see cref="MeridianAuthenticationExtensions"/>). Headers:
/// <c>X-Meridian-User</c> (required), <c>X-Meridian-UserId</c>, <c>X-Meridian-Roles</c> (comma separated).
/// </summary>
public sealed class DevelopmentAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "MeridianDevelopment";
    public const string UserHeader = "X-Meridian-User";
    public const string UserIdHeader = "X-Meridian-UserId";
    public const string RolesHeader = "X-Meridian-Roles";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(UserHeader, out var user) || string.IsNullOrWhiteSpace(user))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var name = user.ToString();
        var id = Request.Headers.TryGetValue(UserIdHeader, out var uid) && !string.IsNullOrWhiteSpace(uid) ? uid.ToString() : name;
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, id),
            new(ClaimTypes.Name, name),
            new("preferred_username", name),
        };
        if (Request.Headers.TryGetValue(RolesHeader, out var roles))
        {
            claims.AddRange(roles.ToString().Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(r => new Claim(ClaimTypes.Role, r)));
        }

        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, SchemeName, ClaimTypes.Name, ClaimTypes.Role));
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, SchemeName)));
    }
}
