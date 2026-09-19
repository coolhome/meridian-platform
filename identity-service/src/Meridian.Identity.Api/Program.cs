using Meridian.Identity.Api.Directory;
using Meridian.Identity.Api.Endpoints;
using Meridian.ServiceDefaults;

var builder = WebApplication.CreateBuilder(args);
builder.AddMeridianServiceDefaults("identity-service");
builder.Services.AddOpenApi();
builder.Services.Configure<DirectoryOptions>(builder.Configuration.GetSection(DirectoryOptions.SectionName));
builder.Services.AddSingleton<IDirectory, ConfigurationDirectory>();

var app = builder.Build();
app.UseMeridianServiceDefaults();
app.MapOpenApi().AllowAnonymous();
app.MapIdentityEndpoints();
app.Run();

public partial class Program;
