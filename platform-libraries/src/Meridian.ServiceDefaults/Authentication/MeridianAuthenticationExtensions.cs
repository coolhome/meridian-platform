using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Identity.Web;

namespace Meridian.ServiceDefaults.Authentication;

public static class MeridianAuthenticationExtensions
{
    public static IServiceCollection AddMeridianAuthentication(this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment)
    {
        var section = configuration.GetSection(MeridianAuthOptions.SectionName);
        var options = section.Get<MeridianAuthOptions>() ?? new MeridianAuthOptions();
        services.Configure<MeridianAuthOptions>(section);

        if (string.Equals(options.Mode, AuthModes.Development, StringComparison.OrdinalIgnoreCase))
        {
            if (!environment.IsDevelopment())
            {
                throw new InvalidOperationException(
                    $"{MeridianAuthOptions.SectionName}:Mode=Development is only permitted when ASPNETCORE_ENVIRONMENT=Development.");
            }

            services.AddAuthentication(DevelopmentAuthenticationHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, DevelopmentAuthenticationHandler>(DevelopmentAuthenticationHandler.SchemeName, _ => { });
        }
        else
        {
            services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
                .AddMicrosoftIdentityWebApi(configuration.GetSection("AzureAd"));
            services.AddSingleton<IClaimsTransformation, GroupToRoleClaimsTransformation>();
        }

        services.AddAuthorizationBuilder()
            .AddPolicy(MeridianPolicies.Requester, p => p.RequireAuthenticatedUser())
            .AddPolicy(MeridianPolicies.Approver, p => p.RequireRole(MeridianRoles.Approver, MeridianRoles.Administrator))
            .AddPolicy(MeridianPolicies.Administrator, p => p.RequireRole(MeridianRoles.Administrator))
            .AddPolicy(MeridianPolicies.Internal, p => p.RequireRole(MeridianRoles.Service))
            .SetFallbackPolicy(new Microsoft.AspNetCore.Authorization.AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());

        return services;
    }
}
