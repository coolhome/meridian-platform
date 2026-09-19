using Meridian.ServiceDefaults.Authentication;
using Meridian.ServiceDefaults.Middleware;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Meridian.ServiceDefaults.Http;

public static class DownstreamClientExtensions
{
    /// <summary>
    /// Typed client for another Meridian service. Base address from <c>Downstream:&lt;name&gt;:BaseAddress</c>.
    /// Forwards the caller's bearer token (or development headers) and the correlation id.
    /// Standard resilience is applied by <c>ConfigureHttpClientDefaults</c>.
    /// </summary>
    public static IHttpClientBuilder AddMeridianDownstreamClient<TClient>(this IServiceCollection services, IConfiguration configuration, string name)
        where TClient : class
    {
        var baseAddress = configuration[$"Downstream:{name}:BaseAddress"]
                          ?? throw new InvalidOperationException($"Downstream:{name}:BaseAddress is not configured.");
        services.TryAddTransientForwardingHandler();
        return services.AddHttpClient<TClient>(client =>
            {
                client.BaseAddress = new Uri(baseAddress, UriKind.Absolute);
                client.Timeout = TimeSpan.FromSeconds(30);
            })
            .AddHttpMessageHandler<CallerContextForwardingHandler>();
    }

    private static void TryAddTransientForwardingHandler(this IServiceCollection services)
    {
        if (!services.Any(d => d.ServiceType == typeof(CallerContextForwardingHandler)))
        {
            services.AddTransient<CallerContextForwardingHandler>();
        }
    }
}

/// <summary>Copies Authorization, development identity headers and X-Correlation-Id from the inbound request.</summary>
public sealed class CallerContextForwardingHandler(IHttpContextAccessor accessor) : DelegatingHandler
{
    private static readonly string[] ForwardedHeaders =
    [
        "Authorization",
        DevelopmentAuthenticationHandler.UserHeader,
        DevelopmentAuthenticationHandler.UserIdHeader,
        DevelopmentAuthenticationHandler.RolesHeader,
        CorrelationIdMiddleware.HeaderName,
    ];

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var inbound = accessor.HttpContext?.Request;
        if (inbound is not null)
        {
            foreach (var header in ForwardedHeaders)
            {
                if (inbound.Headers.TryGetValue(header, out var value) && !request.Headers.Contains(header))
                {
                    request.Headers.TryAddWithoutValidation(header, (IEnumerable<string?>)value);
                }
            }
        }

        return base.SendAsync(request, cancellationToken);
    }
}
