namespace Meridian.Identity.Api.Directory;

public sealed record DirectoryUser(string Id, string Name, string Email, IReadOnlyList<string> Roles);

/// <summary>Directory of platform users. Production implementation targets Microsoft Graph; see README.</summary>
public interface IDirectory
{
    ValueTask<DirectoryUser?> FindAsync(string id, CancellationToken cancellationToken);

    ValueTask<IReadOnlyList<DirectoryUser>> ListByRoleAsync(string role, CancellationToken cancellationToken);
}

public sealed class DirectoryOptions
{
    public const string SectionName = "Directory";

    public List<DirectoryUser> Users { get; set; } = [];
}
