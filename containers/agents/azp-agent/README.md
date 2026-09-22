# azp-agent

Self-hosted Azure Pipelines agent image for pool `meridian-agents`, run as Container Apps jobs
in the shared tier (`platform-infrastructure/bicep/modules/container-apps-jobs.bicep`:
`caj-mrd-shared-agent`, event-triggered off the pool queue, and
`caj-mrd-shared-agent-placeholder`, started once so a registered-but-offline agent keeps queued
jobs from failing with "no agent found"; both names are `<prefix>`/`<environment>`-derived, `mrd`
and `shared` today).

Built on `acrmrdshared.azurecr.io/base/build-tools:10.0` (`containers/base-images/build-tools`:
.NET 10 SDK, Node 24, PowerShell, GitVersion, CycloneDX, non-root `builder` user), plus Azure
CLI, `jq`, `git`, `unzip`/`zip`, `pipx`, `dotnet-runtime-8.0` (the Azure Artifacts credential
provider `NuGetAuthenticate@1` installs on first use is itself a .NET 8 tool), and three pinned,
sha256-checked binaries: hadolint (will replace `docker run hadolint/hadolint` in
`pipeline-templates/pipelines/extends/container-images.yml` once pipelines-dev's templates
v1.1.0 lands — Container Apps jobs cannot run Docker-in-container, and that template on `main`
still runs `docker run` today), bicep (a plain binary on `PATH` rather than `az bicep install`,
because that command caches under `$HOME/.azure` and `AzureCLI@2` gives every step a fresh
`AZURE_CONFIG_DIR`), and the Azure Pipelines agent itself. See the comment block at the top of
`Dockerfile` for the full tool-to-template mapping, including why `jobs/deploy-static-site.yml`
(`AzureStaticWebApp@0`, also `docker run`-based) needs that same v1.1.0 before it can run here.

## This folder is deliberately outside `base-images/`

`containers/azure-pipelines.yml`'s CI trigger paths only include `base-images/`, so this image is
never built by that pipeline. It is bootstrapped by hand:

```bash
az acr build --registry acrmrdshared --image agents/azp-agent:<version> --file Dockerfile .
```

run from this directory. Bringing it under the `containers` pipeline (its own entry in
`image-manifest.json`, scanned and promoted like the base images) is follow-up work, not done
here — the manifest and the CI trigger paths are pipelines-dev's / this repo's shared
`azure-pipelines.yml`, not something this folder can add on its own.

## Configuration

`start.sh` (adapted from Microsoft's
["Run a self-hosted agent in Docker"](https://learn.microsoft.com/azure/devops/pipelines/agents/docker),
PAT-only, no runtime agent download since the image already bakes one in) reads:

| Variable | Required | Meaning |
| --- | --- | --- |
| `AZP_URL` | yes, validated | `https://dev.azure.com/coolhome` |
| `AZP_TOKEN` | yes, validated | PAT, Agent Pools (Read & manage) scope; written to `/azp/.token` and unset from the environment before the agent runs |
| `AZP_POOL` | yes, validated | `meridian-agents` |
| `AZP_AGENT_NAME` | no | defaults to the container hostname; the placeholder job pins this to `placeholder-agent` so re-running it replaces (`--replace`) the same agent instead of registering a new one each time |
| `AZP_PLACEHOLDER` | no | `1` exits right after `config.sh`, leaving the agent registered but offline; anything else runs one job (`run.sh --once`) and then `config.sh remove`, propagating `run.sh`'s exit code |

## Verification run here (no Docker daemon in this session)

* `hadolint --failure-threshold warning Dockerfile` (v2.12.0 Windows binary, sha256-verified
  against the same release the image pins): clean, no findings even at the default threshold.
* `bash -n start.sh`: clean.
* The Dockerfile was not built (no Docker daemon available). `az acr build` from this directory
  is both the build and the first real verification; run it before pointing
  `platform-infrastructure`'s `agentImageTag` parameter at a new version.
