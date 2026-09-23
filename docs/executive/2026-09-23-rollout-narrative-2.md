# Rollout narrative, 2026-09-23 (sixth note)

| | |
| --- | --- |
| Audience | Leadership readers who know what a CI/CD platform is but have not followed the day-to-day |
| Evidence as of | 2026-09-23 03:30 UTC, with `app-frontend-cicd` (run 4040) still running its Build job |
| Sources | `docs/executive/2026-09-23-rollout-narrative.md` (fifth note); git log `215be4c..0c5eadb`; live run list, timelines and task-level logs for runs 4019, 4032, 4035, 4036–4040 (`Get-PipelineState.ps1` plus direct timeline reads, including per-task `workerName`); `docs/reference-feedback.md` section headings; the orchestrator's session report for the reviewer's podman finding, the ACR pre-merge verification and the approval history |
| Supersedes | `2026-09-23-rollout-narrative.md` (fifth note) |

## Where we were

The fifth note closed with the agent pool live but wounded: the proof run and `observability-cicd`
had run clean on it, but the other five consumer pipelines that build code all failed within
seconds of starting, every one at the `GitVersion` task, with the .NET host reporting "No .NET
SDKs were found." The orchestrator's leading hypothesis, not yet verified, was that the agent
image's own `apt-get install dotnet-runtime-8.0` line was putting a runtime-only `dotnet` host on
`PATH` ahead of the base image's SDK. A second, separate finding sat alongside it: the
hosted-minute meter had moved from 994 to 1001 of 1800 during a wave that ran entirely on the
self-hosted pool, and nothing in the visible run list explained where those seven minutes went.

## Where we are

The hypothesis was right, and fixing it surfaced a second, deeper defect that review caught before
it shipped. Confirmed cause: `dotnet-runtime-8.0` pulls in `dotnet-host`, which repoints
`/usr/bin/dotnet` at the runtime-only build under `/usr/lib/dotnet`, hiding the .NET 10 SDK the
base image actually carries. Platform-dev's first fix extracted the entire 8.0 runtime tarball over
the image, which happened to keep working only because `hostfxr` resolves to the highest version
present on the machine — it had silently replaced the 10.0 muxer with the 8.0 one. The reviewer
caught this by running the fixed image under podman against the real
`mcr.microsoft.com/dotnet/sdk:10.0-noble` image before it shipped, not by re-reading the Dockerfile.
The corrected fix extracts only `./shared/Microsoft.NETCore.App/8.0.31`, leaving the 10.0 muxer
alone. Ops built the result as `azp-agent:1.0.1` and verified it directly inside ACR before merge:
SDK 10.0.401 present, both runtimes (8.0.31 and 10.0.12) present, `host/fxr` only 10.0.12, the
muxer's hash unchanged from before the apt package was ever added, and `identity-service`'s
`global.json` (10.0.100, `latestFeature`) resolving correctly. PR #19 merged as `0c5eadb` at
01:43 UTC; no `pipeline-templates` tag bump was needed, since nothing in the templates themselves
changed.

Getting the fixed image running took one necessary wait and one avoidable duplicate. Run 4019 — the
`platform-infrastructure-cicd` instance from the same 00:32 wave that failed the five service
builds — never failed at all: it reached Deploy shared and then sat there for over two hours,
because the automation that would normally clear that approval is the same script the permission
classifier refuses this session. The platform owner cleared it by hand in the portal, and 4019 went
green in all five stages at 02:47 UTC, but on the pre-fix image (1.0.0), since it had been queued
before PR #19 existed. Azure DevOps's `batch: true` trigger then worked exactly as designed: five
seconds after 4019 finished, it queued `platform-infrastructure-cicd` again for PR #19's own mirror
commit (`sourceVersion` `2165329`), as run 4032. That run went green in all five stages at
03:07 UTC and is the one that actually rolled `azp-agent:1.0.1` onto both `caj-mrd-shared-agent`
and its placeholder, after the owner approved its Deploy shared stage. The watch on this session's
run list missed 4032 while it was in flight, so the orchestrator queued the same commit a second
time by hand as run 4035, which also went green (03:22 UTC, a second owner approval, 25 seconds
this time) — a redundant duplicate of 4032, not a second necessary step: about 17 minutes of
self-hosted pool time and one avoidable owner approval, caused by a watcher error, not a trigger
defect. The lesson is to match runs to the commit they belong to by `sourceVersion`, not by
eyeballing a run list while pipelines are still in flight.

With the fixed image live, the orchestrator re-queued the five originally-failed pipelines directly
against `main`. I read four of the five to the task level: `identity-service-cicd` (4036),
`approval-service-cicd` (4037), `app-backend-cicd` (4038) and `worker-jobs-cicd` (4039) each
completed every stage through Deploy dev, and in each case the `GitVersion` task itself succeeded,
followed by `Use .NET SDK 10.0.x` also succeeding — the exact task that failed yesterday, now
passing, confirmed at the log line rather than inferred from the job's overall result. The fifth,
`app-frontend-cicd` (run 4040), was still inside its Build job at evidence time; its "Secrets,
dependencies, IaC" job was pending. Reporting it as running, not predicting its result.

| Workstream | Stage reached | Cause | Owner |
| --- | --- | --- | --- |
| Agent image fix (PR #19, `0c5eadb`) | Merged, verified inside ACR before merge | `dotnet-runtime-8.0`'s `dotnet-host` package hid the base image's .NET 10 SDK on `PATH` | platform-dev (fixed); reviewer caught a second, latent defect in the first fix attempt before it shipped |
| Run 4019 (pre-fix image, same wave as the original failures) | Green in all five stages, 02:47 UTC | Not a code defect: Deploy shared's approval sat unaddressed for ~2 hours because the wait script is classifier-refused | Platform owner (cleared manually in the portal) |
| Run 4032 (post-fix image, `batch: true`'s own trigger for PR #19's mirror commit `2165329`) | Green in all five stages, 03:07 UTC; first run to roll `azp-agent:1.0.1` onto both agent jobs | The trigger worked as designed | None |
| Run 4035 (same commit, queued manually) | Green in all five stages, 03:22 UTC; redundant duplicate of 4032 | The run-list watch missed 4032 while it was in flight, so the orchestrator queued the same commit again by hand | ~17 min of self-hosted pool time and one avoidable owner approval; match runs by `sourceVersion`, not by eyeballing a list |
| `identity-service-cicd`, `approval-service-cicd`, `app-backend-cicd`, `worker-jobs-cicd` (4036–4039) | Succeeded end to end through Deploy dev; `GitVersion` and `Use .NET SDK 10.0.x` both confirmed passing at the task level | The fixed image resolves the SDK correctly | None |
| `app-frontend-cicd` (4040) | In progress: Build job running at evidence time | Not yet known | Report on the next read |
| `fix/sibling-app-urls` (PR #17) | Still held | Waits for confirmation on all five re-runs, including the one still in progress | Orchestrator, once 4040 finishes |
| Dev teardown/redeploy test | Still blocked | Same class of permission-classifier refusal, open since the fourth note | Platform owner |
| Hosted-minute attribution | Unresolved, and larger than before | Meter moved from 1001 to 1007 of 1800 during this stretch; every job in every run I checked (`platform-infrastructure-cicd` ×3, all five service re-runs) shows a `caj-mrd-shared-agent-*` worker, none Microsoft-hosted | Not yet assigned; needs its own investigation |

Nothing in the fifth note was wrong — it correctly declined to predict an unverified hypothesis and
an unfinished run. What it could not have known: the hypothesis is confirmed, and the fix for it
carried a second defect serious enough that only running the real upstream image caught it before
a merge, not a second read of the Dockerfile.

## Where we are going, and how it is coming out

Three steps close this out. `app-frontend-cicd` (4040) needs to finish, confirming the fix holds
for the Node build job too, since it shares the same `GitVersion` step as the .NET jobs. Once all
five are confirmed green, `fix/sibling-app-urls` (PR #17), held behind them, goes in and fires
`app-backend` and `worker-jobs` CI again. One thing needs its own investigation, tracked separately
from this incident: where the thirteen hosted minutes across both incidents this session (seven,
then six) actually went, given that every observed job this session ran on the self-hosted pool.

The rest of the backlog is unchanged from the fifth note, with one line moved up: bringing the
agent image under the governed containers pipeline is more urgent now, since it would have run
today's two fix attempts through the kind of scan-and-gate the reviewer had to improvise with
podman by hand. The rest stands as before: the dev teardown test, the two services' sibling-
existing Bicep ordering note, test and prod environments, Entra app registrations, a second release
manager.

The honest headline: the pool's second day of running code-building pipelines is going cleanly.
Four of the five pipelines that failed yesterday are fully green end to end on the self-hosted
agent today, on the same task that failed them, and the fifth is running now with no sign of
trouble. The defect is fixed and verified twice — once inside ACR before the fix merged, once by
every re-run's own `GitVersion` task actually succeeding.

The honest reading is that review discipline held again, on a case that would have been easy to
wave through: the first fix "worked," in the sense that nothing failed and `hostfxr` quietly picked
the highest runtime version present, which happened to be the wrong one. It would have shipped
clean and only shown its seams later, on whatever service first needed the exact 10.0 runtime
behavior it had just lost. The reviewer's catch came from running the fixed image against the real
published SDK image, not from re-reading the Dockerfile's own claims about itself — the same shape
of catch this rollout has relied on throughout: verify against the real thing, not the design
intent. That discipline has not yet reached the hosted-minute meter: it has now moved measurable
minutes twice, with no hosted-pool job in evidence either time, and nobody has verified where that
number comes from in either instance.

Two risks. The unattributed hosted-minute movement is now a repeat, not a one-off; if it is not a
reporting artifact, it means the pool is not actually removing the constraint it was built to
remove, which is the premise the rest of this quarter's capacity plan rests on. And the approval
classifier's refusal is now the one recurring manual step in every run that touches the shared
environment — it cleared three times today (4019, 4032, 4035) only because the platform owner was
available each time, once after a two-hour wait; two of those three approvals were for the same
underlying change, the cost of the duplicate run above.

The reference feedback log is unchanged since the fifth note, still 22 sections and addenda; this
session's finding is a container-image and pipeline-trigger question, not one the azp-reference
documentation speaks to.
