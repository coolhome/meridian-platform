using Meridian.ServiceDefaults.Authentication;
using Meridian.ServiceDefaults.Middleware;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Meridian.ServiceDefaults;

public static class MeridianServiceDefaultsExtensions
{
    /// <summary>
    /// Registers telemetry, health checks, ProblemDetails, resilient HTTP clients, correlation
    /// ids and platform authentication/authorization. Call first in Program.cs.
    /// </summary>
    public static WebApplicationBuilder AddMeridianServiceDefaults(this WebApplicationBuilder builder, string serviceName)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentException.ThrowIfNullOrWhiteSpace(serviceName);

        // Connection string comes from APPLICATIONINSIGHTS_CONNECTION_STRING (Container App secret ref from Key Vault).
        builder.Services.AddApplicationInsightsTelemetry();
        builder.Services.AddSingleton<ITelemetryInitializer>(new CloudRoleNameInitializer(serviceName));

        builder.Services.AddProblemDetails();
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddSingleton<CorrelationIdMiddleware>();

        builder.Services.AddHealthChecks()
            .AddCheck("self", () => HealthCheckResult.Healthy(), tags: ["live"]);

        builder.Services.ConfigureHttpClientDefaults(http =>
        {
            http.AddStandardResilienceHandler();
        });

        builder.Services.AddMeridianAuthentication(builder.Configuration, builder.Environment);
        return builder;
    }

    /// <summary>Wires the middleware pipeline and health endpoints. Call before mapping endpoints.</summary>
    public static WebApplication UseMeridianServiceDefaults(this WebApplication app)
    {
        ArgumentNullException.ThrowIfNull(app);

        app.UseExceptionHandler();
        app.UseStatusCodePages();
        app.UseMiddleware<CorrelationIdMiddleware>();
        app.UseAuthentication();
        app.UseAuthorization();

        app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = r => r.Tags.Contains("live") }).AllowAnonymous();
        app.MapHealthChecks("/health/ready").AllowAnonymous();
        return app;
    }
}
