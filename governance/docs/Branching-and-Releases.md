# Branching and releases

## Model

Trunk-based. `main` is always deployable. Short-lived branches named
`feature/AB#1234-short-description`, `fix/AB#1234-...`, `chore/...`. Releases that need
stabilisation branch as `release/2026.09` and are mirrored to Azure Repos like `main`.

## Commits and PRs

* Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, `infra:`) with a scope equal to the
  folder name: `feat(approval-service): reject self-approval`.
* Every PR links a work item (`AB#<id>` in title or description). The Azure Repos linking policy
  and the GitHub PR template both ask for it.
* Squash merge only. Merge commits and rebase merges are disabled by policy.

## Versioning

GitVersion runs per Azure Repo in `ContinuousDelivery` mode. `main` produces `X.Y.Z` with a
pre-release counter; the pipeline tags `vX.Y.Z` on the Azure Repo when the prod stage succeeds.
Packages from `platform-libraries` are versioned the same way and published to the `meridian`
feed; consumers bump explicitly.

## Template releases

`meridian-pipeline-templates` tags `vMAJOR.MINOR.PATCH`. Consumers pin `ref: refs/tags/...`.
Breaking parameter changes bump MAJOR. Rollout is opt-in per consumer; the templates CI compiles
every consumer against the candidate before the tag is cut.
