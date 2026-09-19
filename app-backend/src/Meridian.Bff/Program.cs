using Meridian.Bff.Clients;
using Meridian.Bff.Endpoints;
using Meridian.ServiceDefaults;
using Meridian.ServiceDefaults.Http;

var builder = WebApplication.CreateBuilder(args);
builder.AddMeridianServiceDefaults("app-backend");
builder.Services.AddOpenApi();
builder.Services.AddMeridianDownstreamClient<IdentityClient>(builder.Configuration, "Identity");
builder.Services.AddMeridianDownstreamClient<ApprovalsClient>(builder.Configuration, "Approvals");
builder.Services.AddScoped<IIdentityClient>(sp => sp.GetRequiredService<IdentityClient>());
builder.Services.AddScoped<IApprovalsClient>(sp => sp.GetRequiredService<ApprovalsClient>());
builder.Services.AddScoped<DashboardService>();

var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins(allowedOrigins)
    .AllowAnyHeader()
    .WithMethods("GET", "POST")
    .WithExposedHeaders("X-Correlation-Id")));

var app = builder.Build();
app.UseCors();
app.UseMeridianServiceDefaults();
app.MapOpenApi().AllowAnonymous();
app.MapApiEndpoints();
app.Run();

public partial class Program;
