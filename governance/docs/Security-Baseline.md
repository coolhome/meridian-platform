# Security baseline

Mapped to the azp-reference hardening checklist tiers.

## Tier 1

* Microsoft-hosted `ubuntu-24.04` (pinned, not `-latest`) or the platform's own `meridian-agents`
  self-hosted pool (ADR 0008); the pool's Agent Pools PAT in the `shared` Key Vault is the one
  recorded, scoped exception to workload identity (ADR 0006).
* Workload identity federation for every Azure service connection (ADR 0006).
* Job authorization scope limited to the project; referenced-repo scoped tokens on
  (`governance/policies/project-pipeline-settings.json`).
* Fork builds disabled; no secrets to PR builds.
* Consumer input reaches scripts only through typed parameters mapped to variables and `env:`.

## Tier 2

* Templates pinned to tags; container base images pinned by digest in base-image Dockerfiles;
  task major versions pinned.
* SBOM (CycloneDX via `dotnet CycloneDX` / `@cyclonedx/cyclonedx-npm`) published as an artifact
  for every build.
* NuGet package source mapping and `RestoreLockedMode`; npm `ci` with lock file.
* Pipeline YAML lives on protected branches and is reviewed before it runs.

## Tier 3

* Runtime containers run as non-root on chiseled images with no shell.
* Container Apps ingress restricted; internal services are internal-only.

## Tier 4

* Gitleaks (secrets) and Trivy (SCA, IaC, container) run in every PR; SARIF published as an
  artifact. Secret findings and critical CVEs gate; the rest is advisory until baselined.
* Repo policies block `*.pfx`, `*.pem`, `*.p12`, `*.key` files.
* Diagnostic settings send pipeline audit and Key Vault access logs to Log Analytics.
