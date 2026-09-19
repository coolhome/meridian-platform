# Onboarding a new service

1. Create the folder in the GitHub monorepo from the closest existing service. Keep the layout:
   `src/`, `tests/`, `infra/`, `pipelines/pr-validation.yml`, `azure-pipelines.yml`, `Dockerfile`,
   `GitVersion.yml`, `README.md`.
2. Add an entry to `repos.manifest.json` (folder, repo name, tier `service`, owners, area path,
   two pipelines: `cicd` and `pr`).
3. Add the area path to `governance/teams/teams.json` under the owning team.
4. Add the service to `platform-infrastructure` (managed identity + RBAC) and to
   `observability` (alert rules loop).
5. Run `pwsh tooling/Sync-GovernanceOverlay.ps1` to stamp the overlay files.
6. Run `pwsh tooling/Test-RepoBoundaries.ps1` locally.
7. Open the PR. When merged, the sync workflow creates the Azure Repo, pipelines and policies.
8. Authorize the new pipelines on environments if the manifest run reports it could not
   (first run of a new pipeline creates the project build service identity).
