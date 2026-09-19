using System.Net;
using Meridian.Approval.Api.Application;
using Meridian.Approval.Api.Domain;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Cosmos.Linq;

namespace Meridian.Approval.Api.Infrastructure;

public sealed class CosmosOptions
{
    public const string SectionName = "Cosmos";
    public string AccountEndpoint { get; set; } = string.Empty;
    public string DatabaseName { get; set; } = "meridian";
    public string ContainerName { get; set; } = "approvals";
}

internal sealed class CosmosApprovalRepository(Container container) : IApprovalRepository
{
    public async Task<ApprovalRequest?> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        try
        {
            var key = id.ToString("D");
            var response = await container.ReadItemAsync<ApprovalDocument>(key, new PartitionKey(key), cancellationToken: cancellationToken);
            return response.Resource.ToDomain();
        }
        catch (CosmosException ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<IReadOnlyList<ApprovalRequest>> ListAsync(ApprovalQuery query, CancellationToken cancellationToken)
    {
        IQueryable<ApprovalDocument> q = container.GetItemLinqQueryable<ApprovalDocument>();
        if (query.Status is { } status)
        {
            var s = status.ToString();
            q = q.Where(d => d.Status == s);
        }

        if (query.RequestedBy is { } requestedBy)
        {
            q = q.Where(d => d.RequestedBy == requestedBy);
        }

        if (query.Approver is { } approver)
        {
            q = q.Where(d => d.Approvers.Contains(approver));
        }

        if (query.OverdueOnly)
        {
            var pending = nameof(ApprovalStatus.Pending);
            q = q.Where(d => d.Status == pending && d.DueAt != null && d.DueAt < query.Now);
        }

        var results = new List<ApprovalRequest>();
        using var iterator = q.OrderByDescending(d => d.CreatedAt).ToFeedIterator();
        while (iterator.HasMoreResults)
        {
            foreach (var doc in await iterator.ReadNextAsync(cancellationToken))
            {
                results.Add(doc.ToDomain());
            }
        }

        return results;
    }

    public async Task AddAsync(ApprovalRequest request, CancellationToken cancellationToken)
    {
        var doc = ApprovalDocument.From(request);
        await container.CreateItemAsync(doc, new PartitionKey(doc.Id), cancellationToken: cancellationToken);
    }

    public async Task UpdateAsync(ApprovalRequest request, CancellationToken cancellationToken)
    {
        var doc = ApprovalDocument.From(request);
        await container.ReplaceItemAsync(doc, doc.Id, new PartitionKey(doc.Id), cancellationToken: cancellationToken);
    }
}
