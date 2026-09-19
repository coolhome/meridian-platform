namespace Meridian.ServiceDefaults.Authentication;

public sealed class MeridianAuthOptions
{
    public const string SectionName = "Meridian:Auth";

    /// <summary><see cref="AuthModes.EntraId"/> (default) or <see cref="AuthModes.Development"/>.</summary>
    public string Mode { get; set; } = AuthModes.EntraId;

    /// <summary>Entra ID group object id -> platform role (e.g. Approver). Applied as a claims transformation.</summary>
    public Dictionary<string, string> RoleMappings { get; set; } = new(StringComparer.OrdinalIgnoreCase);
}

public static class AuthModes
{
    public const string EntraId = "EntraId";
    public const string Development = "Development";
}

public static class MeridianRoles
{
    public const string Requester = "Requester";
    public const string Approver = "Approver";
    public const string Service = "Service";
    public const string Administrator = "Administrator";
}

public static class MeridianPolicies
{
    public const string Requester = "meridian:requester";
    public const string Approver = "meridian:approver";
    public const string Internal = "meridian:internal";
    public const string Administrator = "meridian:administrator";
}
