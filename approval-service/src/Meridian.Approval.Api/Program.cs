using Meridian.Approval.Api.Endpoints;
using Meridian.Approval.Api.Infrastructure;
using Meridian.ServiceDefaults;

var builder = WebApplication.CreateBuilder(args);
builder.AddMeridianServiceDefaults("approval-service");
builder.Services.AddOpenApi();
builder.Services.AddExceptionHandler<DomainExceptionHandler>();
builder.Services.AddApprovalInfrastructure(builder.Configuration);

var app = builder.Build();
app.UseMeridianServiceDefaults();
app.MapOpenApi().AllowAnonymous();
app.MapApprovalEndpoints();
app.Run();

public partial class Program;
