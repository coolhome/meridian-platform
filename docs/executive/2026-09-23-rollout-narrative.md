# Rollout narrative, 2026-09-23 (fifth note)

| | |
| --- | --- |
| Audience | Leadership readers who know what a CI/CD platform is but have not followed the day-to-day |
| Evidence as of | 2026-09-23 01:05 UTC, after the pin-bump wave from templates v1.1.0 finished: all six of its consumer pipelines have a result |
| Sources | `docs/handoff-7.md`; git log `40f871b..215be4c`; live run list, timelines and task logs for runs 4016–4025 (`Get-PipelineState.ps1` plus direct timeline/log reads on runs 4020, 4023 and 4025); `gh run list --workflow=sync-to-azure-repos.yml`; `docs/reference-feedback.md` section headings; the pipeline-templates and platform-infrastructure source (`pipeline-templates/jobs/build-dotnet.yml`, `steps/gitversion.yml`, `steps/dotnet-setup.yml`, `containers/agents/azp-agent/Dockerfile`, `platform-infrastructure/bicep/modules/container-apps-jobs.bicep`); the orchestrator's session-seven report for the PR sequence, the PAT and the approval-classifier refusal |
| Supersedes | `2026-09-22-rollout-narrative.md` (including its 12:05 UTC postscript) |

## Where we were

The fourth note and its postscript closed with the agent pool half-built and one gate left: the
platform owner had just stored the agent PAT in the shared vault, the flag that creates the two
Container Apps jobs had merged, and its infrastructure run was still in progress when the session
ended. Three pull requests sat prepared and held in order: the pool-creation run itself, a proof
run that moves the templates repository's own CI onto the pool, and templates v1.1.0, which moves
every consumer onto it. The plan for the next session was three steps: read the infrastructure
run, register the placeholder agent, and merge the three pull requests in order. Minutes stood at
967 of 1800.

## Where we are

All three steps ran. The infrastructure run created both Container Apps jobs, the placeholder
agent registered, and the proof run (PR #15) went green on the pool at essentially no cost. Then
templates v1.1.0 (PR #16) merged and moved every consumer onto the pool in one wave, which has now
finished, and that wave is where today's real finding sits: five of its six consumer pipelines
failed within seconds of starting their build job, on a defect that two rounds of review and three
preview compiles did not and could not have caught, because it only shows up when a job actually
runs on the new agent.

| Pipeline or workstream | Stage reached | Cause | Owner of the fix |
| --- | --- | --- | --- |
| Container Apps agent jobs (infra run 3997) | Deployed; verified live | Ran as designed once the PAT existed | None |
| Placeholder agent registration | Succeeded (`caj-mrd-shared-agent-placeholder-b3w35eb`) | `placeholder-agent` registered in `meridian-agents`, offline, enabled, as designed | None |
| `pipeline-templates-ci` proof run (run 4016) | Green on the pool, 3m47s wall clock | First real job ever run on `meridian-agents`; no defects | None |
| `identity-service-cicd`, `approval-service-cicd`, `app-backend-cicd`, `worker-jobs-cicd` (runs 4020–4022, 4024) | Failed at the `GitVersion` task in the Build job, 2–3 seconds after it started | `steps/gitversion.yml` runs `dotnet tool install --global GitVersion.Tool` before the job's own `UseDotNet@2` step (`steps/dotnet-setup.yml`); on the new agent that early step finds "No .NET SDKs were found" | pipelines-dev (step order in `pipeline-templates/jobs/build-dotnet.yml`); platform-dev to confirm what the agent image actually has installed, since its own Dockerfile says the base image already carries the .NET 10 SDK |
| `app-frontend-cicd` (run 4023) | Same failure, same task | Same `GitVersion` step is shared by the Node build job too; this repo carries no `global.json`, and the muxer still reports zero installed SDKs, not just a version mismatch | Same as above |
| `observability-cicd` (run 4025) | Succeeded end to end (7.5 min wall clock); the wave's only consumer to finish clean | This pipeline is Bicep-only, has no Build/GitVersion job, so it was never exposed to the defect | None |
| `governance-ci`, `pipeline-templates-ci` (second run, same push) | Green | Neither touches GitVersion or a language SDK | None |
| Dev environment (base eleven pipelines) | Unchanged, green since the third note | No change today | None |
| Shared approval stage, `platform-infrastructure-cicd` | Blocked on a human | The session's automation refused `Approve-PendingApprovals.ps1 -Wait` this session even though `.claude/settings.local.json` allows it | Platform owner: approve in the portal, or decide how approvals run when this refusal recurs |
| Dev teardown/redeploy test | Still not run live | Same class of permission refusal, open since the fourth note | Platform owner |

Two things this note corrects. First, the fourth note's plan assumed that a template preview-
compiled clean and reviewed twice would run cleanly once an agent existed; it did not, for the
five pipelines that build code, on a step-ordering defect no compile check exercises (a preview
compile proves a pipeline's YAML expands; it does not run any step). Second, the failure is not a
version mismatch: `app-frontend-cicd` has no `global.json` to pin a required SDK version, and its
GitVersion step still reports zero installed SDKs on the agent, which is a stronger claim than "the
wrong version" — it says the .NET SDK the image's own Dockerfile documents is not there to find,
or is not where this step looks for it, and that has not yet been checked against the running
image directly (`dotnet --list-sdks` inside a live container, not yet done). The orchestrator's
leading hypothesis, not yet verified, is that the image's own `apt-get install dotnet-runtime-8.0`
line (`containers/agents/azp-agent/Dockerfile`, around line 88) puts a runtime-only `dotnet` host
on `PATH` ahead of the base image's SDK, so the first `dotnet` command any step runs resolves to a
host that can run applications but reports no SDKs to install a global tool with; platform-dev is
diagnosing and fixing the image on that lead, pipelines-dev the step order.

The hosted-minute meter moved from 994 to 1001 of 1800 during the wave, seven minutes total. That
is not yet attributed to a specific run: every job in this wave ran on the self-hosted pool, which
does not draw from the Microsoft-hosted quota, and the per-run "Minutes" figures in the table above
are wall-clock duration (finish time minus start time), not hosted-minute consumption, so they
cannot be used to charge the five failures for this cost. Which run or job actually drew the seven
minutes is an open question, not yet answered.

## Where we are going, and how it is coming out

Four steps stand between here and every pipeline running cleanly on its own agent. First,
platform-dev or an ops read confirms what is actually installed on the deployed
`azp-agent:1.0.0` image, since the Dockerfile's own comments and the observed failure disagree.
Second, pipelines-dev fixes `pipeline-templates/jobs/build-dotnet.yml` (and its Node equivalent) so
`GitVersion` no longer depends on an SDK that may or may not already be on the machine before
`UseDotNet@2` runs — this is a template change, so it ships as a new tag under the same
lockstep-pin rule as v1.1.0. Third, the fix is preview-compiled and the five failed pipelines are
re-run on the pool to confirm the Build job now gets past GitVersion into the actual build, test
and SBOM steps, not just past the one task that failed today. Fourth, now that the wave has
finished, `fix/sibling-app-urls` (PR #17), held behind it, goes in.

After that, the backlog is unchanged from the fourth note except for one addition: bringing the
agent image under the governed containers pipeline (already backlogged, so it gets the same SARIF
scan and Promote gate every other image gets) is now also the mechanism that would have caught a
missing SDK layer before this wave ran, which makes it worth doing sooner rather than later. The
rest of the backlog stands: the dev teardown test, the two services' sibling-existing Bicep
ordering note, test and prod environments, Entra app registrations for the four services, and a
second release manager.

The honest headline: two of the seven pipelines that ran on the new pool today finished clean
(the templates repository's own proof run and `observability-cicd`); the other five, every one of
them a pipeline that builds code, failed on their first real job on it, all on the same defect, all
within seconds, before any of them reached a test or a deploy stage. The honest
reading is that this is the first defect in the whole rollout that beat the review process rather
than being caught by it — six other defects this build (two found in review before any merge per
the fourth note's postscript, plus four earlier in the session) were all caught by a reviewer or a
preview compile before a run spent money on them. This one could not be, because preview-compile
checks that a pipeline's YAML expands correctly, not that its steps execute correctly on the
specific agent that will run them; the gap between "compiles" and "runs" is exactly what a first
real execution is for, and today was the pool's first real execution for code-building pipelines.
That is consistent with convergence, not thrash: the defect is one cause, found once, and the fix
is a known kind of change (step order, or an image layer) rather than a new class of problem.

Three risks. The agent image's actual contents are unverified against its own documentation until
someone runs `dotnet --list-sdks` inside the live container; until then, every .NET and Node
pipeline stays effectively off the pool, whichever of the two explanations turns out to be true.
The permission classifier's refusal of `Approve-PendingApprovals.ps1 -Wait` this session, despite
the settings file allowing it, is a second instance of a refusal the working agreement already
flags as a decision to escalate, not retry (handoff-7's finding was a different script); every run
that reaches the shared approval now needs a portal click or a repeat of that investigation until
the platform owner decides how approvals should run. And the pool was built to remove hosted
minutes as a constraint for these five pipelines; until the fix lands, every retry of them keeps
spending minutes exactly as before, with about a week left in September and the meter at 1001 of
1800 (up seven minutes over the wave, cause not yet attributed).

The reference feedback log is unchanged since the fourth note, still 22 sections and addenda; this
session's finding is a template-design and image-build question, not one the azp-reference
documentation speaks to, so nothing has been added there yet.
