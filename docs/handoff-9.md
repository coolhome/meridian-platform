# Handoff 9: a backlog assessment, four owner decisions, and three workflows stopped mid-build (2026-09-23, session eight)

Supersedes the next-steps of `handoff-8.md`. Identifiers in `handoff-2.md` still apply.

## The finding that matters

**A relayed mid-turn owner message gets read by running subagents as the only user voice, and
they abandon their assigned task without saying so.** While three implementation workflows ran
in the background this session, the owner sent a message that the harness relayed into each
running subagent. Two of them — `pipelines-dev` building templates v1.2.0, `tooling-dev` building
the drift-report/Entra-personas tooling PR — treated that relayed message as their actual
instruction, dropped the task the workflow had assigned them, and wrote a reply to the owner's
message instead. Both workflows still recorded them as `"done"`. Only `ops`'s verification step
caught it, by diffing the branch instead of trusting the summary: `pipeline-templates/` in
`feat/templates-v1.2.0` came back byte-identical to v1.1.0, no throwaway mirror branch was pushed,
no `az acr run` was executed. `feat/approval-drift-entra-personas` came back with zero diff.
**Neither branch contains the work its `[done]` claimed.** Treat every "done" from a workflow-run
dev agent as unverified until its actual diff is inspected, especially after any mid-turn owner
message; re-dispatch with wording that states the task is the orchestrator's delegation on the
owner's behalf, not a new ask from the owner.

Second: a full backlog assessment (8 read-only assessors plus a reviewer cross-check) closed five
open items outright and reversed one prior claim. The reviewer rejected an assessor's "exact
hosted-minute reconciliation" between Meridian and the owner's separate AI-GoWild project sharing
the same org grant — the usage meter lags (1005 → 1007 moved with no hosted job queued) — so
`handoff-8`'s unattributed-minutes item is now **attribution, not exact accounting**, and closed
as such. Full detail in "What happened, in order" below.

Third: the owner made four decisions this session (approval links + persona accounts, test/prod
subscription reuse, Entra app shape, approval-drift reporting posture) and asked to evaluate
PSRule as an enforcement path for the naming-convention doc `pipelines-dev` had just written.
None of the four decisions or the PSRule direction reached working code this session — see
State.

## State

`main` still at `54ed473` (unchanged since `handoff-8.md`). **Nothing merged this session, no
pipeline run queued, no Azure resource changed.** Live read at session start: every run since the
v1.1.0 wave (4032-4042) green, hosted minutes 1007 of 1800, nothing running.

Housekeeping done directly (no PR, no code touched): the four worktrees `handoff-8` marked safe
to remove (`azp-test-proof`, `azp-test-templates`, `azp-test-agentimg`, `azp-test-services`) and
their local branches were deleted. A stray, mangled redirect-target file named `` `0`].{n `` at
the repo root (an earlier agent's shell escaping error) was deleted; confirmed gone.

No sixth-session narrative was written. The owner invoked `/exec-narrative` at the end of the
session, then stopped before the skill ran. `docs/executive/` still ends at
`2026-09-23-rollout-narrative-2.md` (session seven's sixth note). Run `/exec-narrative` first
thing next session if a seventh note is wanted — the backlog assessment and owner decisions below
are exactly the kind of material it asks for.

### Worktrees now open

| Worktree | Branch | Contents | Verdict |
| --- | --- | --- | --- |
| main checkout | `docs/naming-segment-lengths` | `governance/docs/Architecture.md` +81/-13, uncommitted (this handoff adds to the same checkout, also uncommitted) | content unverified, see below |
| `azp-test-v1.2.0` | `feat/templates-v1.2.0` | `repos.manifest.json` (+7/-3: `templatesRef` v1.2.0, `allowedTemplateRefs` [v1.1.0, v1.2.0], new `containers-agent-image` pipeline entry) and `platform-infrastructure/bicep/modules/container-apps-jobs.bicep` (+12/-1: `pollingInterval` 30→10, sourced comment) | **do not merge**: `pipeline-templates/` untouched, no consumer pins, boundary check would fail |
| `azp-test-envvalues` | `feat/test-prod-values` | `governance/environments/environments.json`, 10 lines changed each way | partial, unverified — pipelines-dev was stopped mid-run; inspect before trusting |
| `azp-test-tooling` | `feat/approval-drift-entra-personas` | empty (0 files changed) | tooling-dev abandoned the task per the finding above |

All branches are local only; nothing pushed to any remote or mirror.

## What happened, in order

| Done | Where |
| --- | --- |
| Backlog assessment: 8 read-only owner-typed assessors + reviewer cross-check, workflow `wf_74f9f0dc-fa3` | full JSON in `journal.jsonl` under `...\subagents\workflows\wf_74f9f0dc-fa3\` |
| CLOSED — hosted-minute leak: no Meridian job runs on hosted agents; every job template branches on `agentPool`, all 18 pins checked pass `platform`, `governance-ci` is hosted by design, run 3997 was the pre-pool bootstrap. Remaining minutes belong to the owner's separate AI-GoWild project (build ids 3992-4015, 4026-4034) sharing the org's 1800-minute grant and single hosted slot | reviewer cross-check corrected "exact reconciliation" to attribution (meter lags) — FYI to owner, no action |
| CLOSED — sibling Bicep ordering: resolved by PR #17 (`4be9f74`); only platform/data `existing` refs remain | verified by re-grep, not re-run |
| CLOSED — Promote skip key: NuGet half already handled (`--skip-duplicate`, `library.yml:133`); container defect already fixed (PR #9 path filter). A commit+Dockerfile skip key was rejected: it would suppress the weekly upstream-patch promotion | note: do not re-queue a producer to prove this — it deliberately re-fires all four services |
| CLOSED — warm agent: `minExecutions=1` at 2 vCPU/4 GiB costs ~$155/month (Container Apps jobs bill the active rate); declined under ADR 0007. Free lever: `pollingInterval` 30→10 (see `azp-test-v1.2.0` above) | platform-dev research, riding the v1.2.0 PR |
| CLOSED — dead template tags: v1.0.9 stays in `allowedTemplateRefs` through the next lockstep bump; deleting mirror tag refs buys nothing and risks a classifier refusal | no action |
| Cross-check correction: pool compute is **not** uncapped — ADR 0008:97-101 puts current use at ~168k of a 180k vCPU-second grant at 2 vCPU/4 GiB | record superseded from any earlier "effectively uncapped" framing |
| Cross-check finding: a manifest-only merge fires no Azure pipeline, but the sync workflow (`sync-to-azure-repos.yml:66-69`) runs `Initialize-AzureDevOps.ps1 -SkipServiceConnections` automatically per `Get-ChangedFolders.ps1:36`, which converges `ExtendsChecks` — a manifest edit is not a no-op | new backlog awareness item |
| Cross-check finding: `containers/image-manifest.json` is a live trigger path for `containers-base-images` — do not edit it casually | new backlog awareness item |
| Cross-check finding: the planned agent-image pipeline's trigger path must be `agents/azp-agent` (mirror root is the `containers` folder); it needs a `repos.manifest.json` pipeline entry (`New-AdoPipelines.ps1`) to be registered and cannot be preview-compiled before merge | folded into the v1.2.0 plan below |
| Cross-check finding: an exact-version image channel needs an opt-in immutable-tag guard, because Promote force-moves on digest change | folded into the v1.2.0 plan below |
| Reviewer produced a full PR1 (templates v1.2.0) sequencing plan | see "Do next" step 2 |
| Reviewer identified 6 NEW backlog items (a)-(f), listed below | Backlog |
| Owner asked once, decided four items final (approvals/personas, test/prod scope, Entra app shape, approval-drift posture) | Owner decisions below |
| Owner asked to consider PSRule for naming/policy enforcement; orchestrator verified live file state (below) rather than trusting recollection | facts below; design workflow `wf_6352099f-1da` |
| `pipelines-dev` wrote the naming segment/length documentation into `governance/docs/Architecture.md` (workflow `wf_59ab04db-c1d`), +81/-13, main checkout, branch `docs/naming-segment-lengths`, uncommitted | see "Naming convention" below — **unverified** |
| Three implementation workflows (`wf_cc11e4b7-40f` templates v1.2.0, `wf_2e3baab4-fb8` owner-decisions impl, `wf_6352099f-1da` PSRule design) and the naming doc's two verifiers + docs-keeper sweep were all stopped (`TaskStop`) around 12:30 UTC when the owner ended the session | see State and Do next |

## Owner decisions (2026-09-23, asked once, final)

1. **Approvals**: for now, the owner approves in the portal; wants **links** to pending approvals
   (`https://dev.azure.com/coolhome/Meridian/_build/results?buildId=<id>`). Wants **persona
   accounts** (release-manager / QA-lead approvers, app roles) created via an owner-run script to
   test with. The resulting ADR must say these owner-controlled personas exercise the mechanics
   of four-eyes approval but are not a real four-eyes control.
2. **Test/prod**: same subscription and tenant as dev, suffix `ch2609`, values-only change,
   nothing deploys from this alone. Alert e-mail address is **still not named** — owner action.
3. **Entra**: an owner-run, idempotent script. One shared API app (identity, approval,
   app-backend v2 tokens), one SPA app, a Service role for `worker-jobs`'s managed identity. No
   Graph permissions granted to any pipeline identity.
4. **Approval-check drift** (live prod approval count 1 vs. `environments.json`'s 2;
   `Initialize-AzureDevOps.ps1` skips existing approval checks around line 292;
   `Get-AdoIdentity` resolves groups by display name only): **report only**, owner applies any
   correction in the portal.

None of these four have working code yet; see `azp-test-envvalues` (partial) and
`azp-test-tooling` (empty, abandoned) above.

## Naming convention (governance/docs/Architecture.md)

Owner asked to "add max lengths of segments for naming conventions." Orchestrator scoped it to
documentation only, in the "Resource naming" section of `governance/docs/Architecture.md`
(`pipelines-dev` owns `governance/`); enforcement in Bicep (`@maxLength` decorators) was offered
and declined for this session because it touches four owners' `prefix`/`environment` params and
fires each folder's pipeline — PSRule custom rules are now the preferred enforcement path instead
(see below).

`pipelines-dev`'s pass (workflow `wf_59ab04db-c1d`) is **done but unverified**: two independent
verifiers (an Azure-limits lens, a repo-inventory lens) and the `docs-keeper` sweep were all
stopped before running. What the diff claims, worth checking first:

* The previously documented pattern `{prefix}-{env}-{component}-{type}` was wrong — live names
  are type-first (`ca-mrd-dev-identity-service`, `caj-mrd-shared-agent-placeholder`).
* The old table omitted Container Apps jobs, Log Analytics, Static Web Apps, pipeline/agent
  identities, policy assignments and action groups; the new one adds them with pattern, Azure
  limit, longest live name and headroom.
* `caj-mrd-shared-agent-placeholder` is claimed to be exactly 32 characters — believed to be the
  literal Container Apps job name limit — which would pin the `prefix` segment's practical max at
  3, tighter than the manifest schema's declared 2-5 range.
* Two `take()` truncations are flagged: `platform-infrastructure/bicep/modules/policy-assignments.bicep`
  (cap 24, real limit is claimed to be 64 at subscription scope) and
  `observability/alerts/main.bicep`'s `groupShortName` (cap 12, claimed to be a hard ARM property
  max, not slack).

Do not treat any of these as fact until the two verifiers run — this is a documentation-only
change but several of its claims (the 32-char job limit, the 64-char policy-assignment limit, the
12-char `groupShortName` max) are exactly the kind of thing that needs the Azure-limits lens
before it ships.

## PSRule (owner's suggestion, facts verified before scoping)

Verified by reading the files, not from memory: `PSRule.Rules.Azure` 1.45.0 already runs in
`pipeline-templates/steps/bicep-validate.yml` (baseline `Azure.Default`, per-folder
`ps-rule.yaml`, NUnit results) but that step is wired only into
`pipelines/extends/infrastructure.yml` — so only `platform-infrastructure` and `observability`
get PSRule in Azure DevOps today. The five `service.yml` consumers (identity, approval,
app-backend, worker-jobs, app-frontend) get **no PSRule step** in Azure DevOps at all.
`.github/workflows/pr-validation.yml:138-142` runs `Assert-PSRule` per changed folder in GitHub
Actions with no `-Path`/`-Option`/`-Baseline` — stock module only. Only
`platform-infrastructure/ps-rule.yaml` exists anywhere in the repo (it enables `.bicepparam`
expansion). Unverified suspicion, not confirmed: folders with no `ps-rule.yaml` may be analysing
nothing meaningful in the GitHub job.

Direction floated, not built: ship Meridian custom rules (the naming segment/length limits above,
required tags, ADR 0007 cost posture) from `pipeline-templates` for the Azure DevOps side and
from `tooling/` for the GitHub Actions side (`tooling-dev` confirmed
`Test-RepoBoundaries.ps1`'s self-containment check only binds mirrored folders, so a shared rule
set under `tooling/` does not violate the boundary rule); extend `bicep-validate` to
`service.yml` (a genuine template behaviour change — new tag, `allowedTemplateRefs`, every
consumer re-pinned); publish SARIF into `CodeAnalysisLogs`; new rules advisory before gating.

`pipelines-dev` and `tooling-dev` each saved a memory note on this (read them, not summarized
twice here):
`C:\Users\TheComputer\Desktop\azp-test\.claude\agent-memory\pipelines-dev\naming-enforcement-psrule-option.md`
and
`C:\Users\TheComputer\Desktop\azp-test\.claude\agent-memory\tooling-dev\psrule-pr-validation-coverage.md`.

A design workflow (`wf_6352099f-1da`: lab run in a scratch copy, research, fit, synth, critique)
was **stopped during evidence gathering** — rerun it next session. Its lab scratch directory may
still hold partial output:
`C:\Users\THECOM~1\AppData\Local\Temp\claude\c--Users-TheComputer-Desktop-azp-test\a5aeabc1-c771-4994-9030-82254500624c\scratchpad\psrule-lab`
(confirmed present at session end — `bin`, `modules`, `out`, `repo`, `rules`, `run-psrule.ps1` —
but it is session scratch and may be cleaned before next session). The owner may also want this
written up as an `exec-narrative` what-if assessment (stated preference: what-ifs go to
`docs/executive`).

## Workflow scripts (full task text, for re-dispatch)

All under
`C:\Users\TheComputer\.claude\projects\c--Users-TheComputer-Desktop-azp-test\a5aeabc1-c771-4994-9030-82254500624c\workflows\scripts\`:

| Script | Covers |
| --- | --- |
| `backlog-assessment-session8-wf_74f9f0dc-fa3.js` | the 8-assessor + reviewer backlog pass (already run; see above) |
| `templates-v1-2-0-build-wf_cc11e4b7-40f.js` | templates v1.2.0 build task text — **rerun this**, `pipelines-dev` declined it last time (see the finding) |
| `owner-decisions-impl-wf_2e3baab4-fb8.js` | test/prod values, tooling (drift report, personas, Entra scripts), ADR 0009 |
| `psrule-extension-design-wf_6352099f-1da.js` | the stopped PSRule lab/design workflow |
| `naming-segment-max-lengths-wf_59ab04db-c1d.js` | the naming doc author + its two stopped verifiers |

## Do next, in order

1. **Decide the PSRule ride-along scope** — rerun `wf_6352099f-1da` (or a fresh design pass) to
   a finished recommendation before committing templates v1.2.0, since extending
   `bicep-validate` to `service.yml` is a template version decision.
2. **Rerun templates v1.2.0** end to end: `gitversion.yml` + `sbom-dotnet.yml` reuse the image's
   preinstalled `GitVersion.Tool`/CycloneDX when versions match (add `CYCLONEDX_VERSION` to
   `variables/common.yml`); `container-images.yml` gets an optional per-image repository (default
   `base/<name>`), an optional smoke test (`az acr run`, base64 payload), an optional immutable
   tag; new `containers/pipelines/agent-image.yml` (`agentPool: hosted`, path `agents/azp-agent`,
   channel `1.0.2`, immutable, smoke test asserting SDK 10.0 + runtimes 8.0/10.0 +
   `/opt/dotnet-tools`); `consumers.json`; all 19 pins; the manifest edit already staged in
   `azp-test-v1.2.0` (orchestrator's). Before merge: `ops` preview-compile plus in-image script
   tests (skip path on `azp-agent:1.0.1`, install path on `mcr` `dotnet/sdk:10.0-noble`, smoke
   test PASS on 1.0.1 and FAIL on 1.0.0). After merge: give the owner the Deploy-shared approval
   link (owner decision 1). Verify the actual diff before trusting any "done" (see the finding).
3. **Verify and merge the naming doc**: rerun the two stopped verifiers (Azure-limits lens,
   repo-inventory lens) plus the `docs-keeper` sweep against the uncommitted
   `governance/docs/Architecture.md` in the main checkout before it ships.
4. **Finish and verify the test/prod values PR** (`azp-test-envvalues`, partial diff — inspect
   before trusting; pipelines-dev was stopped mid-run).
5. **Rebuild the tooling PR** (`azp-test-tooling` is empty — the task never actually ran): drift
   report, individual-user approvers, owner-run `New-EntraAppRegistrations.ps1` and
   `New-MeridianPersonas.ps1`, plus ADR 0009 recording the persona-accounts caveat from owner
   decision 1.
6. **Sunday 2026-09-27 03:00 UTC**: `containers-base-images` runs on the pool for the first time
   at v1.1.0+ (hadolint binary and the digest guard have never run live); its Promote on `shared`
   needs the owner's portal approval, which re-fires the four services. Give the owner the link
   ahead of time.
7. Work backlog items (a)-(f) below.
8. Carried: the teardown/redeploy exercise (owner action, open since `handoff-7.md`).

## Backlog

New this session (from the reviewer's cross-check):

* (a) Sunday 03:00 UTC `containers-base-images` run — see Do next 6.
* (b) `platform-libraries-cicd` has not run since v1.1.0 (last run 3964, session seven) — prove
  it with the next real library commit, not a re-queue.
* (c) The deployed dev SPA cannot reach the BFF: `VITE_API_BASE_URL` is never set
  (`node-build-test.yml:35-36`; `api.ts:46` defaults to `''`), the Free-tier SWA has no linked
  backend, and `/api` 404s are rewritten to `index.html` 200 by
  `public/staticwebapp.config.json`. CORS/redirect-URI need a design that neither hard-codes the
  random SWA hostname nor adds a sibling `existing` reference — an assessor's "derive CORS from
  the existing SWA resource" idea was rejected on that basis.
* (d) `containers/acr-tasks/base-images.yaml` and `containers/scripts/Register-AcrTasks.ps1`
  describe an ACR Task that would bypass the scan-and-Promote gate; a live `az acr task list`
  shows none registered. Delete or mark unused — `platform-dev`, then `docs-keeper`.
* (e) Nobody measures Container Apps free-grant consumption; add a monthly `ops` read.
* (f) Live approval-check state drifts from `environments.json` (prod live 1 vs. file 2);
  `Initialize-AzureDevOps.ps1` skips existing approval checks (~line 292);
  `Get-AdoIdentity` resolves groups by display name only. Report-only per owner decision 4.

Carried from `handoff-8.md`, still open: bring `containers/agents/azp-agent/` under the governed
containers pipeline (folds into templates v1.2.0's `agent-image.yml`, Do next 2);
`steps/gitversion.yml`'s redundant `dotnet tool install` (same PR); the teardown/redeploy test
(owner action); a second release manager (folds into owner decision 1's persona work); any dead
template tags once v1.1.0 is fully confirmed (closed this session as not worth doing, see above).

## Traps this session

* **A relayed mid-turn owner message reaches running subagents as if it were their instruction.**
  See the finding at the top. After any mid-turn owner message sent while workflows are running,
  check each affected agent's actual diff before trusting its "done", and re-dispatch with
  wording that makes clear the task is the orchestrator's delegation, not a new ask from the
  owner mid-flight.
* **"Exact reconciliation" of a shared usage meter is not achievable and should not be claimed.**
  The hosted-minutes meter moved 1005→1007 with no Meridian hosted job queued; it lags and mixes
  with the owner's other project in the same org. Record shared-meter findings as attribution,
  not exact accounting — the reviewer's correction this session.
* **Do not re-queue a producer pipeline to prove a promotion/skip-key idea.** It deliberately
  re-fires all four downstream services. Prove such ideas by inspection or on the next real
  commit, not by a manual re-queue.
* **A manifest-only edit is not a no-op merge.** The sync workflow
  (`sync-to-azure-repos.yml:66-69`, `Get-ChangedFolders.ps1:36`) runs
  `Initialize-AzureDevOps.ps1 -SkipServiceConnections` automatically on any manifest change,
  which converges `ExtendsChecks` — treat a `repos.manifest.json` edit as triggering, not inert.
* **`containers/image-manifest.json` is a live trigger path for `containers-base-images`.** Do
  not edit it casually while testing something else.
* Carried from `handoff-8.md`, still valid: identify a commit's run by `sourceVersion`, not a
  sorted top-N run listing; a classifier refusal on an allowlisted command is final, not a bug to
  route around; `az.cmd` strips backslash-escaped quotes inside `--cmd`; verify what a fix writes
  to disk, not only that its pipeline result is green.
