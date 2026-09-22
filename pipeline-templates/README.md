# meridian-pipeline-templates

The deployment control plane (ADR 0002). Every Meridian pipeline is a thin entry file that
`extends` one of four templates here. Environments carry a *required template* check listing
exactly these paths, so nothing else can deploy.

| Template | For | Consumer passes |
| --- | --- | --- |
| `pipelines/extends/service.yml` | dotnet-api, dotnet-worker, node-spa | `serviceName`, `kind`, `environments` (default dev, test, prod), optional `dotnet`/`node`/`container`/`infra` objects, optional `preBuildSteps` (allow-listed tasks only), `smokePath` (default `/health/ready`, empty disables the smoke test), `prodStrategy` (`canary` default, or `runOnce`), `deploy` (default true) |
| `pipelines/extends/infrastructure.yml` | Bicep at subscription or resource-group scope | `name`, `templatePath`, `scope`, `parametersPattern`, `resourceGroupPattern`, `additionalParameters`, `environments` (default shared, dev, test, prod), `psRuleBaseline`, `deploy` |
| `pipelines/extends/library.yml` | NuGet packages plus optional per-environment infra | `name`, `packProjects`, `feed` (bare feed name, default `meridian`; the template pushes to the project-scoped id `$(System.TeamProject)/<feed>`), optional `dotnet`/`infra` objects, `environments`, `preBuildSteps`, `deploy` |
| `pipelines/extends/container-images.yml` | Base images built with ACR Tasks | `images[]` (`name`, `context`, `channel`), `deploy` |

Object keys the templates read: `dotnet.sdkVersion`, `dotnet.projects`, `dotnet.testProjects`,
`dotnet.publishProject`, `dotnet.lockedMode`; `node.version`, `node.workingDirectory`,
`node.outputDirectory`; `container.repository`, `container.context`, `container.dockerfile`,
`container.baseImage`; `infra.templatePath`, `infra.parametersPattern`,
`infra.resourceGroupPattern`.

## Rules baked in

* Consumer entry file owns the only root `variables:` block. Templates declare variables at
  stage or job scope.
* Deployment always happens in `deployment:` jobs bound to an environment.
* `preBuildSteps` may only contain `task:` steps from the allow-list in
  `jobs/governance-prebuild-steps.yml`: `DownloadSecureFile@1`, `Cache@2`, `UseDotNet@2`,
  `UseNode@1`, `NuGetAuthenticate@1`, `NpmAuthenticate@0`, `CopyFiles@2`, `ExtractFiles@1`.
  Anything else fails to compile with a `__governance-rejected-...__` template-not-found error.
* Every build produces test results, coverage, a CycloneDX SBOM and Gitleaks + Trivy SARIF.
* Images are built by `az acr build` into the shared registry and scanned before deploy.
* Prod service deploys use the canary strategy with 10 and 50 percent waves.
* Agents are pinned to `ubuntu-24.04`.

## Stages

Every stage names its `dependsOn` explicitly, and promotion is chained: `Deploy_test` waits for
`Deploy_dev`, `Deploy_prod` for `Deploy_test` (or for the nearest earlier environment the
consumer lists). Package, Deploy, Publish, Promote and Release stages are skipped on pull-request runs.
`prod` deploy stages take the exclusive lock with `lockBehavior: sequential`.

| Template | Stage graph |
| --- | --- |
| `service.yml` | `Build` and `Scan` in parallel -> `Package` (dotnet kinds only; depends on both) -> `Deploy_<env>` per environment (depends on Build, Scan, Package where it exists, and the previous environment's deploy) -> `Release` (tags the repo; only when `prod` is listed) |
| `infrastructure.yml` | `Validate` -> per environment `WhatIf_<env>` (depends on Validate and on the previous environment's `Deploy_<env>`, in the order shared -> dev -> test -> prod) -> `Deploy_<env>` |
| `library.yml` | `Build` (build, then pack) and `Scan` in parallel -> `Publish` (deployment job on the `packages` environment; pushes to the project-scoped feed) -> `Deploy_<env>` per environment when `infra.templatePath` is set (depends on Publish and the previous environment's deploy) -> `Release` (when `prod` is listed) |
| `container-images.yml` | `Validate` (hadolint plus scan) -> `Build` (one job per image; each publishes its own SARIF artifact `CodeAnalysisLogs-image-base-<name>`) -> `Promote` (deployment job on `shared`; moves the channel tag) |

## Versioning

Tags `vMAJOR.MINOR.PATCH`. Consumers pin `ref: refs/tags/vX.Y.Z`. A release moves three things
in one change: `templatesRef` and `allowedTemplateRefs` in `repos.manifest.json`, and the `ref:`
in every consumer. The sync workflow creates a missing tag from `allowedTemplateRefs` at the
mirrored `main` commit and never moves an existing one; the bootstrap lists every allowed ref in
the required-template checks; `tooling/Test-RepoBoundaries.ps1` fails a consumer pin that differs
from `templatesRef`. `azure-pipelines.yml` here compiles every consumer listed in
`consumers.json` against the current commit using the pipelines preview API before a tag is cut.
The two producers exclude their entry files from CI on purpose (`containers` triggers only on files under
`base-images/` and on `image-manifest.json`; `platform-libraries` excludes `azure-pipelines.yml` and
`pipelines/*`), so a pin bump neither rebuilds the base images nor publishes a new library
prerelease; a template change to `container-images.yml` or `library.yml` is exercised by the
`containers` weekly schedule or by ops queueing those pipelines
(`tooling/Start-EnvironmentDeploy.ps1 -Environment dev -IncludeShared -Only containers-base-images`
and `-Only platform-libraries-cicd`).

## Layout

```
pipelines/extends/   entry points (the only paths allowed by the required-template check)
stages/              stage templates composed by the entry points
jobs/                job templates (build, scan, package, deploy)
steps/               step templates (checkout, gitversion, sbom, scanners, bicep, smoke)
variables/           variable templates (common, per-environment)
```
