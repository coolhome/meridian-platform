# meridian-identity-service

Resolves who the caller is and what platform roles they hold. Other services trust the
bearer token directly (via `Meridian.ServiceDefaults`), but the SPA and the BFF ask this
service for the resolved principal, the approver directory and the discovery document.

| Endpoint | Auth | Purpose |
| --- | --- | --- |
| `GET /me` | any signed-in user | Resolved principal: id, name, roles |
| `GET /approvers` | any signed-in user | Users who hold the Approver role (for the "pick approvers" UI) |
| `GET /users/{id}` | Approver or Service | Directory lookup |
| `GET /.well-known/meridian-identity` | anonymous | Auth mode, tenant, role names |
| `GET /health/live`, `/health/ready` | anonymous | Probes |

## Directory provider

`IDirectory` has one implementation here, `ConfigurationDirectory`, backed by the
`Directory:Users` section (seeded in `appsettings.Development.json`). The production
implementation against Microsoft Graph plugs into the same interface; it is intentionally not
in this repository until the Graph application permission is approved.

## Run locally

```bash
export ASPNETCORE_ENVIRONMENT=Development
dotnet run --project src/Meridian.Identity.Api
curl -H "X-Meridian-User: alice" -H "X-Meridian-Roles: Approver" http://localhost:5100/me
```

Development auth mode is refused outside `ASPNETCORE_ENVIRONMENT=Development`.

## Build the image locally

```bash
dotnet publish src/Meridian.Identity.Api -c Release -o .publish
docker build -t identity-service:local .
```
