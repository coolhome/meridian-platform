# meridian-platform-libraries

Two NuGet packages published to the `meridian` Azure Artifacts feed, plus the queue
definitions they imply.

| Package | Contents |
| --- | --- |
| `Meridian.Messaging.Contracts` | Message envelope, `ApprovalRequested` / `ApprovalDecided` / `ApprovalAuditEntry` payloads, queue names, serializer. JSON Schemas in `schemas/` are the contract; a test fails when the C# types drift. |
| `Meridian.ServiceDefaults` | `AddMeridianServiceDefaults()`: Application Insights with cloud role name, ProblemDetails, health endpoints, standard HTTP resilience, correlation-id middleware, Entra ID **or** Development-mode authentication with group -> role mapping, authorization policies, downstream token forwarding. |

`queues.json` is the single list of Storage Queues. `infra/queues.bicep` loads it and creates
each queue plus its poison queue on the environment's platform storage account.

## Versioning

GitVersion (`GitVersion.yml`, `next-version: 1.0.0`). The pipeline packs with the build
number and pushes to the feed from a `deployment` job bound to the `packages` environment,
so the required-template and branch-control checks apply to package publishing too.

## Consuming

Services pin an explicit version:

```xml
<PackageReference Include="Meridian.ServiceDefaults" Version="$(MeridianPackageVersion)" />
```

with `nuget.config` package source mapping (`Meridian.*` only from the feed).

## Local

```bash
dotnet build
dotnet test
dotnet pack -c Release -o ./.publish/packages -p:Version=0.0.1-local
```
