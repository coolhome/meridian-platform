# meridian-pipeline-templates

The deployment control plane (ADR 0002). Every Meridian pipeline is a thin entry file that
`extends` one of four templates here. Environments carry a *required template* check listing
exactly these paths, so nothing else can deploy.

| Template | For | Consumer passes |
| --- | --- | --- |
| `pipelines/extends/service.yml` | dotnet-api, dotnet-worker, node-spa | `serviceName`, `kind`, `agentPool` (`hosted` default, `platform` opt-in; see below), `environments` (default dev, test, prod), optional `dotnet`/`node`/`container`/`infra` objects, optional `preBuildSteps` (allow-listed tasks only), `smokePath` (default `/health/ready`, empty disables the smoke test), `prodStrategy` (`canary` default, or `runOnce`), `deploy` (default true) |
| `pipelines/extends/infrastructure.yml` | Bicep at subscription or resource-group scope | `name`, `templatePath`, `scope`, `parametersPattern`, `resourceGroupPattern`, `additionalParameters`, `agentPool` (`hosted` default, `platform` opt-in; see below), `environments` (default shared, dev, test, prod), `psRuleBaseline`, `deploy` |
| `pipelines/extends/library.yml` | NuGet packages plus optional per-environment infra | `name`, `packProjects`, `feed` (bare feed name, default `meridian`; the template builds the project-scoped feed URL `.../<project>/_packaging/<feed>/nuget/v3/index.json` and pushes with `dotnet nuget push --skip-duplicate`), `agentPool` (`hosted` default, `platform` opt-in; see below), optional `dotnet`/`infra` objects, `environments`, `preBuildSteps`, `deploy` |
| `pipelines/extends/container-images.yml` | Base images built with ACR Tasks | `images[]` (`name`, `context`, `channel`), `agentPool` (`hosted` default, `platform` opt-in; see below), `deploy` |

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
* `agentPool` (`hosted` default, `platform` opt-in) picks the pool at compile time for every
  stage that declares `pool:`: `hosted` pins `ubuntu-24.04`, `platform` emits `pool: name:
  meridian-agents`, the self-hosted Container Apps jobs pool in the `shared` tier (one agent at
  a time, Linux, no Docker daemon; ADR 0008). `platform` needs an agent already registered in
  the pool (the placeholder ADR 0008 describes) or queued jobs never start. Rollback: set
  `agentPool: hosted` on the consumer, no template change required.
* `node-spa` deploys the built `drop` artifact with the SWA CLI (`npx @azure/static-web-apps-cli
  deploy`), not `AzureStaticWebApp@0`, because that task runs Docker internally and cannot run on
  the `meridian-agents` pool.

## Stages

Every stage names its `dependsOn` explicitly, and promotion is chained: `Deploy_test` waits for
`Deploy_dev`, `Deploy_prod` for `Deploy_test` (or for the nearest earlier environment the
consumer lists). Package, Deploy, Publish, Promote and Release stages are skipped on pull-request runs.
`prod` deploy stages take the exclusive lock with `lockBehavior: sequential`.

| Template | Stage graph |
| --- | --- |
| `service.yml` | `Build` and `Scan` in parallel -> `Package` (dotnet kinds only; depends on both) -> `Deploy_<env>` per environment (depends on Build, Scan, Package where it exists, and the previous environment's deploy) -> `Release` (tags the repo; only when `prod` is listed) |
| `infrastructure.yml` | `Validate` -> per environment `WhatIf_<env>` (depends on Validate and on the previous environment's `Deploy_<env>`, in the order shared -> dev -> test -> prod) -> `Deploy_<env>` |
| `library.yml` | `Build` (build, then pack) and `Scan` in parallel -> `Publish` (deployment job on the `packages` environment; `dotnet nuget push --skip-duplicate` to the project-scoped feed, so a redeploy of an already-published version does not fail the stage) -> `Deploy_<env>` per environment when `infra.templatePath` is set (depends on Publish and the previous environment's deploy) -> `Release` (when `prod` is listed) |
| `container-images.yml` | `Validate` (hadolint from a pinned, checksummed binary, plus scan) -> `Build` (one job per image; each publishes its own SARIF artifact `CodeAnalysisLogs-image-base-<name>`) -> `Promote` (deployment job on `shared`; imports and moves the channel tag; a fresh build always gets a new digest and moves the tag, re-firing the four services by design; the re-import is skipped only when Promote re-runs for a build already promoted under this tag, a stage retry or a redeploy of the same run) |

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
