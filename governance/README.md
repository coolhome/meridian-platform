# meridian-governance

Policies, environments and decisions as code. Nothing here deploys software; everything here
decides *how* software is allowed to reach an environment.

| Path | Purpose | Applied by |
| --- | --- | --- |
| `adr/` | Architecture decision records | humans |
| `docs/` | Published as the **Meridian** code wiki (`.order` controls navigation) | `tooling/Publish-Platform.ps1` |
| `policies/branch-policy-profiles.json` | Branch and repository policy profiles per repo tier (approvers, work-item linking, build validation, required reviewers by path, file size/path/name/case/author-email rules) | `tooling/Set-AdoBranchPolicies.ps1` |
| `policies/project-pipeline-settings.json` | `build/generalsettings` toggles (job auth scope, fork protection, classic pipelines off, shell arg sanitising) | `tooling/Initialize-AzureDevOps.ps1` |
| `environments/environments.json` | Environments (`shared`, `dev`, `test`, `prod`, `packages`), their Azure identities and checks (required template, branch control, business hours, approvals, exclusive lock) | `tooling/Initialize-AzureDevOps.ps1` |
| `teams/teams.json`, `teams/iterations.json` | Teams, area paths, security groups, sprint cadence | `tooling/Initialize-AzureDevOps.ps1` |
| `templates/overlay/` | Files stamped into every mirrored repo (PR template, editorconfig, gitattributes, gitignore, SECURITY.md); drift fails CI | `tooling/Sync-GovernanceOverlay.ps1`, `tooling/Test-RepoBoundaries.ps1` |

## Changing a policy

1. Edit the JSON here in the GitHub monorepo (the mirror is read-only).
2. PR needs three approvals plus Platform Engineering and Security Champions (the
   `governance` profile is applied to this repository too).
3. On merge the sync workflow mirrors the change and re-applies policies, environments and
   checks to every repository.

`azure-pipelines.yml` validates this repository on every mirrored push: JSON well-formedness,
schema shape of the governance files, ADR numbering, and that every doc page is listed in
`docs/.order`.
