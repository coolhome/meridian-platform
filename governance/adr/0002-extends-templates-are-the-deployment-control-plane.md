# ADR 0002: `extends` templates are the deployment control plane

**Status:** Accepted, 2026-09-19. Note 2026-09-22: "opt-in per consumer" describes the mechanism (each consumer carries its own explicit pin; nothing moves a consumer without a change to its file), not staggered adoption. `tooling/Test-RepoBoundaries.ps1` check 6 fails a pin that differs from the manifest `templatesRef`, so in practice every consumer moves in the same release PR; with one team that is the intended cadence. Staggered adoption would need that check to accept any ref in `allowedTemplateRefs`, which is a deliberate change, not a bug.

## Context

The platform team must be able to guarantee that every deployment runs scanning, produces an
SBOM, deploys through `deployment:` jobs bound to environments, and cannot inject arbitrary
scripts into privileged stages. Consumers must still be able to express what their service is.

## Decision

* Every consumer pipeline is a thin entry file that `extends` one of four templates in
  `meridian-pipeline-templates`: `service.yml`, `infrastructure.yml`, `library.yml`,
  `container-images.yml`.
* Consumers pass **data** (service name, kind, environments, project paths). They may pass a
  `preBuildSteps` step list, which the template filters through a compile-time task allow-list.
  Any other step shape makes the pipeline fail to compile (azp-reference example 01 pattern).
* Environments `dev`, `test`, `prod` carry a **required template** check pointing at those four
  templates. A pipeline that does not extend one of them cannot deploy.
* Consumers pin the templates repository to a **tag** (`refs/tags/vX.Y.Z`). New template
  versions roll out **opt-in per consumer** (azp-reference operating model: never flip a shared
  default for all consumers in one commit).
* Only the consumer file declares root-level `variables:`; the templates declare variables at
  stage and job scope (avoids the `'variables' is already defined` compile error).

## Consequences

* A template release is a tag on `meridian-pipeline-templates` plus a PR per consumer that
  bumps `ref:`. The templates CI compiles every consumer against the candidate tag before it is
  cut.
* Consumers cannot add marketplace tasks without a template change, which is intended.
