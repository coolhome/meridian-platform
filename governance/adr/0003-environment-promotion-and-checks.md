# ADR 0003: Environment promotion and checks

**Status:** Accepted, 2026-09-19

## Decision

| Environment | Who deploys | Checks (in evaluation order) |
| --- | --- | --- |
| `dev` | any run of `main` or `release/*` | required template; branch control |
| `test` | after `dev` succeeds | required template; branch control; approval by **QA Leads** (1, requester may not approve, 24 h timeout); business hours 08:00-18:00 Eastern, Mon-Fri |
| `prod` | after `test` succeeds | required template; branch control (`main`, `release/*`, verify branch protection); approval by **Release Managers** (2, requester may not approve, 12 h timeout); exclusive lock, `sequential` |

* Checks live on the environment, owned by the resource owner, never in YAML. `ManualValidation@1`
  is allowed only for cooperative mid-stage pauses (for example "confirm what-if output") and is
  not a governance control.
* Exclusive lock behaviour is `sequential`, because Container App revision promotion is not
  idempotent across runs and `runLatest` would cancel intermediate releases.
* Approval timeouts mark the stage **skipped**, not failed. Retrying the stage re-evaluates every
  check with a fresh approver snapshot.
* Prod deployments of services use a canary strategy with traffic increments of 10 and 50
  percent, smoke tests between waves, and traffic rollback to the previous revision on failure.
