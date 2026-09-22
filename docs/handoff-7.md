# Handoff 7: the agent pool build staged, three merges and a PAT from a green platform (2026-09-22, session six)

Supersedes the next-steps of `handoff-6.md`. Identifiers in `handoff-2.md` still apply.

## The finding that matters

**An auto-mode classifier refusal is a decision, not a transient error; do not retry it.** Early
this session, ops hit a classifier refusal on 2 of 8 `az repos ref delete` calls while deleting
dead mirror tags, and retried them, and the retries went through. Later the same session, ops hit
the same kind of refusal on `Remove-AzureEnvironment.ps1 -Force` ("Auto-Mode Bypass") before it
touched anything, and did **not** retry: it stopped and reported the refusal as an owner action
instead. The second behaviour is the one to keep. A refusal that goes through on retry is not
evidence the action was safe, it is evidence the classifier can be resubmitted past; treating it as
a queue hiccup risks doing exactly what the classifier is there to stop (here, a tag delete; next
time, something that cannot be undone). This is a new trap for `CLAUDE.md`, not yet added because
scribe does not edit `CLAUDE.md` — the orchestrator should add it under "Traps everyone has hit
here". Full account in "Traps this session" below.

Second in importance: the agent pool has real Azure and Azure DevOps state now (a shared Container
Apps environment, a Key Vault, an agent image, a registered pool with every pipeline authorized on
its queue) but **no agent has run a job yet**, and three artifacts are staged and unmerged
(`feat/agent-pool-enable`, `ci/templates-ci-on-pool`, `feat/templates-v1.1.0`). The build is
correctly sequenced, not finished; see "The agent pool build" below for the exact order and why
it cannot be compressed.

## State

`main` at `3b36982`. Since `handoff-6.md` (`9918937`, main clean, no owner action open):

| Commit | PR | What | Merged |
| --- | --- | --- | --- |
| `9279b64` | #11 | Shared Container Apps environment (`cae-mrd-shared`), Key Vault (`kv-mrd-shared-ch2609`), identity (`id-mrd-shared-agents`), two flagged Container Apps jobs behind `agentPoolEnabled=false`, agent image source, `Initialize-AgentPool.ps1`, `Test-PipelineTemplates.ps1` additions, manifest `selfHostedPool` field, and the teardown-script fixes from the reviewer's dry run (StrictMode `.Count`, the `-Pat ?? $env:AZDO_PAT` fallback, should-fixes) | ~10:30 UTC |
| `3b36982` | #12 | Allowlists the owner's object id in Gitleaks (`generic-api-key` false positive in `shared.bicepparam`, introduced by PR #11) | ~10:50 UTC |

Held branches, pushed, **not merged, no PR open**:

| Branch | Worktree | Contents |
| --- | --- | --- |
| `feat/agent-pool-enable` | `C:\Users\TheComputer\Desktop\azp-test-enable` | `agentPoolEnabled = true`; ADR 0008 (new); ADR 0006 status note |
| `ci/templates-ci-on-pool` | (not separately worktreed at time of writing) | Proof run: `pipeline-templates-ci` moved onto the pool as its own commit |
| `feat/templates-v1.1.0` | `C:\Users\TheComputer\Desktop\azp-test-templates` | See "The agent pool build"; now also carries the deploy-name fix below (pipelines-dev, in progress) |

Hosted minutes: 941 of 1800 at the start of the session, 960 of 1800 after run 3991 (see below).
Run 3990 (fired by PR #11) failed at Validate on the Gitleaks finding that PR #12 fixed. **Its
re-run, run 3991 (`platform-infrastructure-cicd`, queued 10:50 UTC, finished ~11:02 UTC, 15 hosted
minutes), went green end to end**: Validate 3.1 min (Gitleaks passed with the allowlist), What-if
shared 1.0 min, Deploy shared 3.2 min (approval recorded 10:55 UTC by the running approver),
What-if dev 1.0 min, Deploy dev 2.2 min. Verified live afterwards: `rg-mrd-shared-platform` now
holds `cae-mrd-shared`, `kv-mrd-shared-ch2609` and `id-mrd-shared-agents` (principal
`a5002b85-2f6e-4285-babc-364ba1295118`), and no `Microsoft.App/jobs` yet (expected — PR #11 kept
`agentPoolEnabled=false`). Vault role assignments: Key Vault Secrets User for the agents identity,
Key Vault Secrets Officer for `25ca776b-...` (the owner); AcrPull for the agents identity on
`acrmrdshared`. `azdo-agent-pat` does not exist in the vault yet — owner action 1 below is still
open. `Initialize-AgentPool.ps1 -Status`: pool 14, queue 198, no agents, no job. The vault and
identity that "The agent pool build" step 1 called for are now confirmed live, not merely merged
as Bicep source.

**New defect found reading run 3991's outputs**: `jobs/deploy-bicep.yml` names the subscription
deployment `<name>-<buildId>`, with no environment suffix. Deploy dev's subscription deployment
therefore reused the same name as Deploy shared's (`platform-3991`) and overwrote it, so
`az deployment sub show` on that name returned empty agent-pool outputs after the run finished; the
vault name had to be read back from the nested `keyvault-shared` resource-group deployment instead.
Harmless this run (both stages target the same subscription and the values happened to match), but
a future run reading `platform-<buildId>` outputs by name for anything that differs between shared
and dev would read the wrong stage's values. Fix in progress on `feat/templates-v1.1.0`
(pipelines-dev): the deployment name will carry `-<environment>`.

The fourth executive narrative, `docs/executive/2026-09-22-rollout-narrative.md` (written 11:01 UTC,
already indexed in `docs/executive/README.md`), supersedes the third and reflects the state up to
but not including run 3991; treat this handoff as the more current source for run 3991 and the
deploy-name defect above.

| Done | Where |
| --- | --- |
| Dead mirror tags v1.0.0–v1.0.7 deleted on `meridian-pipeline-templates` (GitHub never held them; the sync mints tags from `allowedTemplateRefs`, so these were dead weight, not history) | ops, live Azure Repos state |
| Sunday's `containers-base-images` schedule registered, next run 2026-09-27 03:00 UTC; confirmed the shared approval times out at 1440 minutes and marks Promote skipped, not failed, so nothing needs an approver and nothing re-fires on expiry | ops verification |
| Teardown/redeploy readiness: reviewer dry-ran `Remove-AzureEnvironment.ps1 -WhatIf` against live dev inventory (apps 5, data 2, platform 26, keeping the vault and the identity, 8 role assignments, 3 policy assignments) and found two blockers plus should-fixes; all applied in PR #11 | `tooling/Remove-AzureEnvironment.ps1`, PR #11 |
| Self-hosted capacity assessment: Container Apps jobs now, Managed DevOps Pools blocked on `coolhome` being a Microsoft-account-owned org (`TF400813`), the first self-hosted parallel job is free, PAT is the only registration path | `docs/executive/2026-09-22-self-hosted-capacity-assessment.md` |
| Shared Container Apps environment, vault, identity, flagged jobs, agent image source, pool tooling, teardown fixes | PR #11 (`9279b64`) |
| Gitleaks allowlist for the owner's object id | PR #12 (`3b36982`) |
| Agent image built and pushed: `acrmrdshared.azurecr.io/agents/azp-agent:1.0.0`, digest `sha256:b6a11ef4b90137f02e96f141af20426a571c948bb62bd7c5750cdf0546ec49a3`, `az acr build`, 3m15s | ops, ACR `acrmrdshared` |
| Agent pool `meridian-agents` created (pool id 14, project queue 198); every pipeline authorized on the queue, no classifier refusal; no agent registered yet | ops, `tooling/Initialize-AgentPool.ps1 -EnsurePool -AuthorizeAllPipelines` |
| Templates v1.1.0 designed, pushed, rebased on `main`, preview-compiled against a throwaway mirror branch (all 18 consumers expand to `pool: name: meridian-agents` with zero `vmImage`; default path still expands to hosted) | `feat/templates-v1.1.0` |
| Run 3991 (`platform-infrastructure-cicd`) green end to end, 15 hosted minutes; the shared vault, identity and Container Apps environment confirmed live in Azure, no jobs yet | ops verification, `rg-mrd-shared-platform` |

## The agent pool build

**Design** (ADR 0008, `governance/adr/0008-self-hosted-agents-on-container-apps-jobs.md` on
`feat/agent-pool-enable`, not yet on `main`):

* Pool `meridian-agents`, backed by two Container Apps jobs in `shared`: `caj-mrd-shared-agent`
  (event-driven, KEDA `azure-pipelines` scaler, `minExecutions: 0`, `maxExecutions: 1`) and
  `caj-mrd-shared-agent-placeholder` (manual trigger, keeps one agent registered so the pool never
  scales to zero *from empty* — Microsoft Learn: a pool with no placeholder agent fails pipelines
  at queue time, it does not merely delay them). Both 2 vCPU / 4 GiB. One agent at a time, matching
  today's Microsoft-hosted parallelism; a second concurrent job is a $15/month purchase, not a
  redesign.
* Agent image from `base/build-tools:10.0`, run directly as each job's own container
  (`template.containers[].image`), not referenced from pipeline YAML — v1.1.0 uses none of the
  `resources.containers` mechanism.
* PAT scoped to Agent Pools (Read & manage) only, held as Container Apps secret `azdo-agent-pat`
  on both jobs, resolved from `kv-mrd-shared-ch2609` through `id-mrd-shared-agents` at container
  start. Recorded as the one deliberate, scoped exception to ADR 0006 (workload identity
  everywhere); never a pipeline-visible secret or a variable-group value.
* Consumer opt-in: `pipeline-templates` v1.1.0 adds a compile-time `agentPool` parameter (`hosted`
  default, `platform` opt-in) to the four extends templates and every job template that declares a
  `pool:`. `pipeline-templates-ci` moves to the pool unconditionally as the proof run; every other
  consumer pins v1.1.0 with `agentPool: platform` in the same wave (ADR 0002's lockstep-pin rule
  still applies: one `templatesRef` for every consumer).
* Rollback is per consumer: `agentPool: hosted` reverts to Microsoft-hosted at the next run, no
  template change.

**Why the order below cannot be compressed**: a Container Apps job validates its Key Vault secret
reference at creation time, so the vault and the secret must exist in Azure before the jobs
resource is deployed — this is why the PAT step is a hard gate between two infrastructure runs,
not a parallel task. Everything else is dependency order (a pool with no agent fails queued runs
immediately; templates opting into a pool with no authorized queue fail the same way):

1. ~~The pending infra run (post-PR #12) creates the vault and identity in Azure.~~ **Done**: run
   3991 (10:50–11:02 UTC) created and verified them live — see State above.
2. Owner creates the PAT and stores it in `kv-mrd-shared-ch2609` (Owner action 1 below). **This is
   the open blocking step now.**
3. Merge `feat/agent-pool-enable` (`agentPoolEnabled = true`, ADR 0008, ADR 0006 note).
4. A further infra run creates the two Container Apps jobs (the PAT-bearing secret reference now
   resolves, since step 2 already put the secret in the vault the jobs will read from).
5. `Initialize-AgentPool.ps1 -RegisterPlaceholder` — runs `caj-mrd-shared-agent-placeholder` once
   so the pool has its first registered agent.
6. Merge `ci/templates-ci-on-pool`; confirm `pipeline-templates-ci` runs green on the pool (the
   first real proof the whole chain works, at effectively zero hosted minutes).
7. Merge `feat/templates-v1.1.0`; every consumer's pin bump fires the next wave, which now runs on
   the pool instead of the Microsoft-hosted agent.

Reviewer verdict on the v1.1.0 branch (independent, before any merge): correct to merge only after
step 5 — merging it earlier means every consumer run fails at queue time with no agent to route to,
not a slow first run.

## Owner actions

1. **Create a PAT** scoped to Agent Pools (Read & manage), 90-day expiry, and store it:
   ```bash
   az keyvault secret set --vault-name kv-mrd-shared-ch2609 --name azdo-agent-pat --value <pat>
   ```
   Blocks steps 3–7 of "The agent pool build" above.
2. **Unblock the teardown/redeploy exercise**: either allow `pwsh ./tooling/Remove-AzureEnvironment.ps1*`
   and `pwsh ./tooling/Start-EnvironmentDeploy.ps1*` in `.claude/settings.local.json`, or run the
   teardown yourself. Once unblocked, ops resumes at verification, then
   `Start-EnvironmentDeploy.ps1 -Environment dev -ApproveShared -TimeoutMinutes 180` (expected
   90–120 min wall time, 75–100 hosted minutes). Design note for services-dev, from the reviewer's
   dry run: `app-backend/infra/main.bicep` and `worker-jobs/infra/main.bicep` read sibling
   Container Apps as `existing`, so a clean redeploy only works because the libraries completion
   trigger fires the four services in identity, approval, app-backend, worker-jobs order — worth a
   comment in both Bicep files so a future redeploy-order change does not break it silently.

## Do next, in order

1. Get owner action 1 (the PAT) done; it gates everything else in "The agent pool build" (run 3991
   already did step 1, creating the vault it goes into).
2. Merge the `feat/templates-v1.1.0` deployment-name fix (`jobs/deploy-bicep.yml` gets an
   `-<environment>` suffix) before or alongside the rest of v1.1.0 — pipelines-dev has it in
   progress; confirm it lands before trusting any future run's `az deployment sub show` output.
3. Work through agent-pool-build steps 3–7 in order; do not merge `feat/templates-v1.1.0` before
   `ci/templates-ci-on-pool` has proven the pool green.
4. Once v1.1.0 lands, read the resulting wave by `triggerInfo`, not run count (handoff-6's traps
   still apply), and confirm hosted-minute usage stays flat since the wave now runs on the pool.
5. Get owner action 2 (teardown allow-rule or a manual run) done, independent of the pool work;
   it exercises `Remove-AzureEnvironment.ps1` / `Start-EnvironmentDeploy.ps1` for the first time on
   a live `-Force` run.
6. After the pool has carried a few ordinary waves, revisit whether to run the teardown/redeploy
   test on the pool itself (the capacity assessment's recommendation was to prove the pool on
   ordinary traffic first, not stack it under an unproven script the first time).

## Backlog

* `app-backend/infra/main.bicep` / `worker-jobs/infra/main.bicep` depend on redeploy ordering for
  their `existing` sibling lookups (see owner action 2 design note) — services-dev.
* Promote needs a build-invariant skip key so a re-queue of an already-published commit does not
  re-push a duplicate NuGet version (handoff-6's open caveat, still unresolved) — pipelines-dev /
  tooling-dev.
* Bring `containers/agents/azp-agent/` under the containers pipeline instead of a manual
  `az acr build`, so the agent image gets the same SARIF scan and Promote gate every other image
  gets — platform-dev.
* `test` / `prod` environment values, Entra app registrations for the four services, a second
  release manager — all open since `handoff-2.md`, none newly blocking.

## Traps this session

* **A classifier refusal is a decision, not retried.** See "The finding that matters" above. Ops
  retried 2 of 8 refused `az repos ref delete` calls (dead-tag cleanup) and they went through; the
  same session, ops correctly did not retry `Remove-AzureEnvironment.ps1 -Force`'s refusal
  ("Auto-Mode Bypass") and reported it instead. Treat every refusal as final; escalate to the
  owner or add an explicit allow rule, never resubmit the same call.
* **A Container Apps job validates its Key Vault secret reference at creation.** This is why the
  PAT has to be in the vault before the jobs resource deploys, not merely before the job first
  runs — a job created against a not-yet-existing secret fails to create, not just to execute.
  Drives the two-phase infra-run ordering in "The agent pool build".
* **`az pipelines runs artifact download` hits `TF400813` on this org** (same Microsoft-account/
  Entra gap as Managed DevOps Pools and the earlier Entra-token rejection, `docs/handoff.md`
  session two). Use the REST artifact download endpoints with a PAT instead of the CLI subcommand.
* **Gitleaks flags GUIDs assigned in `.bicepparam` files as `generic-api-key`.** The owner's object
  id in `shared.bicepparam` (introduced by PR #11) tripped this; PR #12 allowlisted it by value.
  Any new GUID literal landing in a `.bicepparam` is a candidate false positive — check the
  Validate stage before assuming a real secret leaked.
* **A subscription deployment name with no environment suffix collides across stages.**
  `jobs/deploy-bicep.yml` names each subscription deployment `<name>-<buildId>`; in a pipeline
  that deploys `shared` then `dev` in the same run, both stages produced the same name
  (`platform-3991`), the dev deployment overwrote the shared one, and `az deployment sub show`
  on that name returned dev's (empty) outputs instead of shared's. Read outputs from the nested
  resource-group deployment when in doubt, and check `feat/templates-v1.1.0` landed the
  `-<environment>` suffix fix before trusting `az deployment sub show` by name again.
* **A stage-filtered completion trigger fires at stage completion, not run completion** (carried
  forward from `handoff-6.md`; still the right lens for reading the v1.1.0 wave once it fires —
  anchor detection windows on the producer's queue time and match on `triggerInfo`, not on when
  the producer's run finishes).

## Reference feedback

One addendum added to `docs/reference-feedback.md`, Context 5: `AzureStaticWebApp@0` itself runs
Docker internally, which the no-Docker Container Apps pool cannot use; v1.1.0's static-site deploy
switches to `npx @azure/static-web-apps-cli@2.0.10 deploy` instead. Documented as a design decision
for v1.1.0, not yet observed on a live pool run (no agent has run a job yet this session).
