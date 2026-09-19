# meridian-app-backend

Backend-for-frontend for the SPA. It is the only service the browser talks to. It forwards
the caller's bearer token (or Development headers) to `identity-service` and
`approval-service`, aggregates the dashboard, and applies CORS for the Static Web App origin.

| Endpoint | Downstream |
| --- | --- |
| `GET /api/me` | identity `/me` |
| `GET /api/approvers` | identity `/approvers` |
| `GET /api/approvals?...` | approvals `/approvals` |
| `POST /api/approvals` | approvals `POST /approvals` |
| `GET /api/approvals/{id}` | approvals `/approvals/{id}` |
| `POST /api/approvals/{id}/decision` | approvals `POST /approvals/{id}/decision` |
| `GET /api/dashboard` | identity `/me` + approvals (`mine=requested`, `mine=approving&status=Pending`) |

Downstream ProblemDetails are passed through unchanged (status code and body), so the SPA
sees the domain error codes from approval-service.

## Configuration

| Key | Example |
| --- | --- |
| `Downstream:Identity:BaseAddress` | `https://ca-mrd-dev-identity-service.<env>.azurecontainerapps.io` |
| `Downstream:Approvals:BaseAddress` | `https://ca-mrd-dev-approval-service.<env>.azurecontainerapps.io` |
| `Cors:AllowedOrigins:0` | `https://swa-mrd-dev-app-frontend.azurestaticapps.net` |

## Run locally

```bash
export ASPNETCORE_ENVIRONMENT=Development
dotnet run --project src/Meridian.Bff        # http://localhost:5000, expects identity on 5100 and approvals on 5200
```
