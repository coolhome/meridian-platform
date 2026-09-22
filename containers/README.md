# meridian-containers

Governed base images and the ACR Task that keeps them fresh.

| Image | Upstream | Used by |
| --- | --- | --- |
| `base/dotnet-aspnet:10.0` | `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` | every .NET service (`Dockerfile` `BASE_IMAGE` build arg) |
| `base/dotnet-runtime:10.0` | `mcr.microsoft.com/dotnet/runtime:10.0-noble-chiseled` | console jobs |
| `base/build-tools:10.0` | `mcr.microsoft.com/dotnet/sdk:10.0-noble` + Node 24 + PowerShell | container jobs in pipelines |

`image-manifest.json` lists them; `azure-pipelines.yml` passes it to the
`container-images.yml` template, which builds with `az acr build`, scans with Trivy,
and promotes the channel tag (`10.0`) from a `deployment` job bound to the `shared`
environment (approval by Platform Engineering).

## What runs the pipeline

CI on `main` runs only when a file under `base-images/` or `image-manifest.json` changes. `azure-pipelines.yml`
is deliberately not a trigger path: a template pin bump alone must not rebuild and re-promote the
base images, because re-promoting the `10.0` channel tag fires every .NET service pipeline through
its `baseImage` container resource (the 2026-09-22 pin-bump waves did exactly that). The Sunday
03:00 UTC schedule (`always: true`) still rebuilds weekly. A template change to
`container-images.yml` is exercised by that schedule or by ops queueing the pipeline, accepting on
purpose that Promote re-tags the channel and re-fires the four .NET services:

```bash
pwsh tooling/Start-EnvironmentDeploy.ps1 -Environment dev -IncludeShared -Only containers-base-images
```

## Rebuild chain

1. Microsoft publishes a patched `aspnet:10.0-noble-chiseled`.
2. The ACR Task registered by `scripts/Register-AcrTasks.ps1` has `--base-image-trigger-enabled`
   and rebuilds `base/dotnet-aspnet:10.0` (or the weekly schedule in `azure-pipelines.yml` does).
3. Every .NET service pipeline declares a `resources.containers` entry of type `acr` with a tag
   trigger on `base/dotnet-aspnet`, so services rebuild and redeploy through their normal gates.

## Standards

See `policy/image-standards.md`. Short version: non-root, no shell in runtime images,
OCI labels, pinned upstream channel with digest recorded at build, scanned before promotion.
