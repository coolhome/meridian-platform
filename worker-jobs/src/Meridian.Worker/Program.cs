using Azure.Identity;
using Azure.Storage.Queues;
using Meridian.Messaging.Contracts;
using Meridian.Messaging.Contracts.Events;
using Meridian.ServiceDefaults;
using Meridian.Worker.Jobs;
using Meridian.Worker.Messaging;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);
builder.AddMeridianServiceDefaults("worker-jobs");

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.Configure<MessagingOptions>(builder.Configuration.GetSection(MessagingOptions.SectionName));
builder.Services.Configure<EscalationOptions>(builder.Configuration.GetSection(EscalationOptions.SectionName));
builder.Services.Configure<DownstreamAuthOptions>(builder.Configuration.GetSection(DownstreamAuthOptions.SectionName));

builder.Services.AddSingleton(sp =>
{
    var opts = sp.GetRequiredService<IOptions<MessagingOptions>>().Value;
    var clientOptions = new QueueClientOptions { MessageEncoding = QueueMessageEncoding.Base64 };
    if (!string.IsNullOrWhiteSpace(opts.ConnectionString))
    {
        return new QueueServiceClient(opts.ConnectionString, clientOptions);
    }

    if (string.IsNullOrWhiteSpace(opts.QueueServiceUri))
    {
        throw new InvalidOperationException("Messaging:QueueServiceUri or Messaging:ConnectionString is required.");
    }

    return new QueueServiceClient(new Uri(opts.QueueServiceUri), new DefaultAzureCredential(), clientOptions);
});

builder.Services.AddSingleton<WorkerTelemetry>();
builder.Services.AddSingleton<INotifier, LogNotifier>();
builder.Services.AddSingleton<IAuditWriter, QueueAuditWriter>();
builder.Services.AddSingleton<IMessageHandler<ApprovalRequested>, ApprovalRequestedHandler>();
builder.Services.AddSingleton<IMessageHandler<ApprovalDecided>, ApprovalDecidedHandler>();
builder.Services.AddSingleton(sp => new MessageDispatcher<ApprovalRequested>(
    sp.GetRequiredService<IMessageHandler<ApprovalRequested>>(),
    sp.GetRequiredService<IOptions<MessagingOptions>>().Value.MaxDequeueCount,
    sp.GetRequiredService<ILogger<MessageDispatcher<ApprovalRequested>>>()));
builder.Services.AddSingleton(sp => new MessageDispatcher<ApprovalDecided>(
    sp.GetRequiredService<IMessageHandler<ApprovalDecided>>(),
    sp.GetRequiredService<IOptions<MessagingOptions>>().Value.MaxDequeueCount,
    sp.GetRequiredService<ILogger<MessageDispatcher<ApprovalDecided>>>()));

builder.Services.AddHostedService(sp => new QueueProcessor<ApprovalRequested>(
    sp.GetRequiredService<QueueServiceClient>(), sp.GetRequiredService<MessageDispatcher<ApprovalRequested>>(), sp.GetRequiredService<IOptions<MessagingOptions>>(),
    sp.GetRequiredService<WorkerTelemetry>(), sp.GetRequiredService<ILogger<QueueProcessor<ApprovalRequested>>>(), QueueNames.ApprovalRequested));
builder.Services.AddHostedService(sp => new QueueProcessor<ApprovalDecided>(
    sp.GetRequiredService<QueueServiceClient>(), sp.GetRequiredService<MessageDispatcher<ApprovalDecided>>(), sp.GetRequiredService<IOptions<MessagingOptions>>(),
    sp.GetRequiredService<WorkerTelemetry>(), sp.GetRequiredService<ILogger<QueueProcessor<ApprovalDecided>>>(), QueueNames.ApprovalDecided));

builder.Services.AddTransient<WorkerCredentialHandler>();
builder.Services.AddHttpClient<IApprovalApiClient, ApprovalApiClient>((sp, client) =>
    {
        var baseAddress = sp.GetRequiredService<IOptions<DownstreamAuthOptions>>().Value.BaseAddress;
        client.BaseAddress = new Uri(string.IsNullOrWhiteSpace(baseAddress) ? "http://localhost:5200/" : baseAddress, UriKind.Absolute);
    })
    .AddHttpMessageHandler<WorkerCredentialHandler>();
builder.Services.AddHostedService<EscalationJob>();

builder.Services.AddHealthChecks().AddCheck<QueueHealthCheck>("queues");

var app = builder.Build();
app.UseMeridianServiceDefaults();
app.Run();

public partial class Program;
