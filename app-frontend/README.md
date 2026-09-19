# meridian-app-frontend

React + Vite single-page app on Azure Static Web Apps. Signed-in users see their requests,
raise new ones, and approvers click **Approve** or **Reject**. Every call goes to
`app-backend` (`VITE_API_BASE_URL`), never to the domain services directly.

## Auth

| `VITE_AUTH_MODE` | Behaviour |
| --- | --- |
| `entra` (default) | MSAL (`@azure/msal-browser`) popup sign-in against the tenant/client in `VITE_ENTRA_*`, bearer token for the BFF scope |
| `development` | Sends `X-Meridian-User` / `X-Meridian-Roles` headers chosen in the UI; only honoured by services running in Development auth mode |

## Scripts

```bash
npm ci
npm run dev        # http://localhost:5173, proxies /api to http://localhost:5000
npm test           # vitest + Testing Library
npm run lint
npm run build      # dist/ (includes public/staticwebapp.config.json)
```

## Pipeline

`azure-pipelines.yml` extends `service.yml@templates` with `kind: node-spa`. The deploy
stage runs `infra/main.bicep` (Static Web App), reads the deployment token from the resource at
deploy time (no stored secret) and uploads `dist/` with `AzureStaticWebApp@0`.
