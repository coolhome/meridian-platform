# ADR 0001: GitHub monorepo is the source of truth; Azure Repos hold per-component mirrors

**Status:** Accepted, 2026-09-19

## Context

We want one place to review and change the whole platform, and we want the Azure DevOps
surface (per-repo branch policies, per-repo pipelines, Boards area paths, required reviewers by
path, Artifacts, Environments) exercised as richly as possible. Those two goals pull in opposite
directions: a monorepo is one repo; Azure DevOps governance is per repo.

## Decision

* One GitHub repository holds every component as a top-level folder.
* Every folder marked `mirror: true` in `repos.manifest.json` is mirrored into its own Azure
  Repo with `git subtree split`, preserving per-folder history. `main` and `release/*` are
  mirrored; feature branches are not.
* Azure Repos are **read-mostly**. Direct pushes to `main` are blocked for humans by branch
  policy; only the Sync Automation identity pushes. Emergency hotfixes may be opened as PRs in
  Azure Repos and are back-ported with `tooling/Sync-FromAzureRepos.ps1` (subtree pull).
* Pipelines, environments, checks and Boards live only in Azure DevOps.

## Consequences

* Each folder must build in isolation (see ADR 0004). CI enforces this.
* Version tags are produced per Azure Repo by GitVersion, not in GitHub.
* A rewrite of history in GitHub (rebase of `main`) requires a forced mirror push; the sync
  script refuses unless `-Force` is passed, and the runbook says why.
