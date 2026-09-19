using Microsoft.Extensions.Options;

namespace Meridian.Identity.Api.Directory;

internal sealed class ConfigurationDirectory(IOptionsMonitor<DirectoryOptions> options) : IDirectory
{
    public ValueTask<DirectoryUser?> FindAsync(string id, CancellationToken cancellationToken)
    {
        var user = options.CurrentValue.Users.FirstOrDefault(u =>
            string.Equals(u.Id, id, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(u.Email, id, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(u.Name, id, StringComparison.OrdinalIgnoreCase));
        return ValueTask.FromResult(user);
    }

    public ValueTask<IReadOnlyList<DirectoryUser>> ListByRoleAsync(string role, CancellationToken cancellationToken)
    {
        IReadOnlyList<DirectoryUser> users = options.CurrentValue.Users
            .Where(u => u.Roles.Contains(role, StringComparer.OrdinalIgnoreCase))
            .OrderBy(u => u.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return ValueTask.FromResult(users);
    }
}
