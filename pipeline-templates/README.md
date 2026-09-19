# meridian-pipeline-templates

The deployment control plane (ADR 0002). Every Meridian pipeline is a thin entry file that
`extends` one of four templates here. Environments carry a *required template* check listing
exactly these paths, so nothing else can deploy.

| Template | For | Consumer passes |
| --- | --- | --- |
| `pipelines/extends/service.yml` | dotnet-api, dotnet-worker, node-spa | `serviceName`, `kind`, `environments`, optional `dotnet`/`node`/`container`/`infra` objects, optional `preBuildSteps` (allow-listed tasks only) |
| `pipelines/extends/infrastructure.yml` | Bicep at subscription or resource-group scope | `templatePath`, `scope`, `parametersPattern`, `environments`, `psRuleBaseline` |
| `pipelines/extends/library.yml` | NuGet packages plus optional per-environment infra | `packProjects`, `testProjects`, optional `infra`, `environments` |
| `pipelines/extends/container-images.yml` | Base images built with ACR Tasks | `images[]` |

## Rules baked in

* Consumer entry file owns the only root `variables:` block. Templates declare variables at
  stage or job scope.
* Deployment always happens in `deployment:` jobs bound to an environment.
* `preBuildSteps` may only contain `task:` steps from the allow-list in `jobs/build-dotnet.yml`
  and `jobs/build-node.yml`. Anything else fails to compile with a
  `__governance-rejected-...__` template-not-found error.
* Every build produces test results, coverage, a CycloneDX SBOM and Gitleaks + Trivy SARIF.
* Images are built by `az acr build` into the shared registry and scanned before deploy.
* Prod service deploys use the canary strategy with 10 and 50 percent waves.
* Agents are pinned to `ubuntu-24.04`.

## Versioning

Tags `vMAJOR.MINOR.PATCH`. Consumers pin `ref: refs/tags/vX.Y.Z`. `azure-pipelines.yml` here
compiles every consumer listed in `consumers.json` against the current commit using the
pipelines preview API before a tag is cut.

## Layout

```
pipelines/extends/   entry points (the only paths allowed by the required-template check)
stages/              stage templates composed by the entry points
jobs/                job templates (build, scan, package, deploy)
steps/               step templates (checkout, gitversion, sbom, scanners, bicep, smoke)
variables/           variable templates (common, per-environment)
```
