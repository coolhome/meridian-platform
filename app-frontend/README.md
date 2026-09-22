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

`.npmrc` points every install at the Azure Artifacts feed with `always-auth`, so `npm ci` needs
feed credentials (`npx vsts-npm-auth -config .npmrc`, or a PAT). Without them, install from the
public registry the way the GitHub PR workflow does:

```bash
npm ci --no-audit --no-fund --registry=https://registry.npmjs.org/ --replace-registry-host=always
```

In Azure Pipelines `NpmAuthenticate@0` injects the feed credentials before `npm ci`.

## Pipeline

`azure-pipelines.yml` extends `service.yml@templates` with `kind: node-spa`. The deploy
stage runs `infra/main.bicep` (Static Web App), reads the deployment token from the resource at
deploy time (no stored secret) and uploads `dist/` with `AzureStaticWebApp@0`.
