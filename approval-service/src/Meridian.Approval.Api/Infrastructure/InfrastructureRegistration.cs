using Azure.Identity;
using Azure.Storage.Queues;
using Meridian.Approval.Api.Application;
using Microsoft.Azure.Cosmos;

namespace Meridian.Approval.Api.Infrastructure;

internal static class InfrastructureRegistration
{
    public static IServiceCollection AddApprovalInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddSingleton(TimeProvider.System);
        services.AddScoped<ApprovalService>();

        var storageProvider = configuration["Storage:Provider"] ?? "InMemory";
        if (string.Equals(storageProvider, "Cosmos", StringComparison.OrdinalIgnoreCase))
        {
            var cosmos = configuration.GetSection(CosmosOptions.SectionName).Get<CosmosOptions>() ?? new CosmosOptions();
            if (string.IsNullOrWhiteSpace(cosmos.AccountEndpoint))
            {
                throw new InvalidOperationException("Cosmos:AccountEndpoint is required when Storage:Provider=Cosmos.");
            }

            services.AddSingleton(_ => new CosmosClient(cosmos.AccountEndpoint, new DefaultAzureCredential(), new CosmosClientOptions
            {
                SerializerOptions = new CosmosSerializationOptions { PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase },
                ApplicationName = "approval-service",
            }));
            services.AddSingleton(sp => sp.GetRequiredService<CosmosClient>().GetContainer(cosmos.DatabaseName, cosmos.ContainerName));
            services.AddSingleton<IApprovalRepository, CosmosApprovalRepository>();
        }
        else
        {
            services.AddSingleton<IApprovalRepository, InMemoryApprovalRepository>();
        }

        var messaging = configuration.GetSection(MessagingOptions.SectionName).Get<MessagingOptions>() ?? new MessagingOptions();
        if (string.Equals(messaging.Provider, "StorageQueue", StringComparison.OrdinalIgnoreCase))
        {
            services.AddSingleton(_ =>
            {
                var options = new QueueClientOptions { MessageEncoding = QueueMessageEncoding.Base64 };
                if (!string.IsNullOrWhiteSpace(messaging.ConnectionString))
                {
                    return new QueueServiceClient(messaging.ConnectionString, options);
                }

                if (string.IsNullOrWhiteSpace(messaging.QueueServiceUri))
                {
                    throw new InvalidOperationException("Messaging:QueueServiceUri or Messaging:ConnectionString is required when Messaging:Provider=StorageQueue.");
                }

                return new QueueServiceClient(new Uri(messaging.QueueServiceUri), new DefaultAzureCredential(), options);
            });
            services.AddSingleton<IEventPublisher, StorageQueueEventPublisher>();
        }
        else
        {
            services.AddSingleton<IEventPublisher, NullEventPublisher>();
        }

        return services;
    }
}
