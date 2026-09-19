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

## Rebuild chain

1. Microsoft publishes a patched `aspnet:10.0-noble-chiseled`.
2. The ACR Task registered by `scripts/Register-AcrTasks.ps1` has `--base-image-trigger-enabled`
   and rebuilds `base/dotnet-aspnet:10.0` (or the weekly schedule in `azure-pipelines.yml` does).
3. Every service pipeline declares a `resources.containers` entry of type `acr` with a tag
   trigger on `base/dotnet-aspnet`, so services rebuild and redeploy through their normal gates.

## Standards

See `policy/image-standards.md`. Short version: non-root, no shell in runtime images,
OCI labels, pinned upstream channel with digest recorded at build, scanned before promotion.
