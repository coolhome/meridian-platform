# Environments and promotion

See ADR 0003 for the decision. This page is the operator view.

## Stage order in every service pipeline

`Build` -> `Scan` -> `Package` -> `Deploy_dev` -> `Deploy_test` -> `Deploy_prod`

Each `Deploy_*` stage contains exactly one `deployment:` job bound to the environment of the
same name, so environment checks always run.

## What blocks a promotion

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Stage shows **skipped** with no failure | Approval timed out | Retry the stage; approvers are re-snapshotted |
| Stage waits with "Business hours" | Outside 08:00-18:00 Eastern Mon-Fri | Wait, or a Release Manager overrides the check |
| "This pipeline needs permission to access a resource" | Pipeline not authorized on the environment, service connection or variable group | `tooling/New-AdoPipelines.ps1 -GrantPermissions` |
| "Required template" check failed | Entry file does not `extends` a template from `meridian-pipeline-templates` at the allowed path | Fix the entry file |
| Branch control failed | Source branch is not `main` or `release/*`, or branch is unprotected | Deploy from a protected branch |
| Exclusive lock waiting | Another run holds `prod` | Wait; locks are `sequential` |

## Canary in prod

1. `deploy`: new Container App revision created with 0% traffic, suffix = short SHA.
2. `routeTraffic`: `strategy.increment` percent moved to the new revision (10, then 50).
3. `postRouteTraffic`: smoke test against the revision FQDN and error-rate query.
4. `on.success`: 100% to the new revision, previous revision deactivated.
5. `on.failure`: 100% back to the previous revision, new revision deactivated.
