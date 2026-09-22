# Rollout narrative, 2026-09-22 (fourth note)

| | |
| --- | --- |
| Audience | Leadership readers who know what a CI/CD platform is but have not followed the day-to-day |
| Evidence as of | 2026-09-22 11:01 UTC, with infrastructure run 3991 past its shared deployment and its dev stages still running |
| Sources | `docs/handoff-7.md` (draft); git log `9918937..3b36982`; run timelines and the Gitleaks SARIF of run 3990; the shared resource group, agent pool and registry read live; `docs/executive/2026-09-22-self-hosted-capacity-assessment.md`; hosted resource usage; `docs/reference-feedback.md` |
| Supersedes | `2026-09-21-rollout-narrative.md` |

## Where we were

The third note closed with the platform deployed: every one of the eleven pipelines green at least once, the four services running in dev with healthy endpoints, infrastructure green the hour the platform owner granted the missing role, and the meter at 941 of 1800 hosted minutes with eight days left in the month. It named the minute cap as the binding constraint and pointed at the self-hosted agent move the first assessment had deferred until the first green deploy.

## Where we are

The platform is unchanged and green; the work of the day was building the capacity that removes the minute cap. Two assessments settled the shape (Container Apps jobs; the Microsoft-managed alternative needs an organization connected to Entra ID, which this one is not), two pull requests put the shared half in place, and the run applying it has created the environment, the vault and the identity the agent pool needs. The templates release that moves every pipeline onto the pool is built, reviewed and compiled against all eighteen consumers, and is held until the pool has an agent.

| Pipeline or workstream | Stage reached | Cause | Owner of the fix |
| --- | --- | --- | --- |
| Dev environment (all eleven pipelines) | Deployed and green since the third note | No change today | None |
| Shared tier for the agent pool (run 3991) | Deploy shared complete; What-if dev and Deploy dev running | Container Apps environment, Key Vault and agents identity created; the agent jobs stay behind a flag until the PAT exists | None; the run finishes on its own |
| Run 3990, the first attempt | Failed at Validate in 3 minutes | Gitleaks matched the owner's object id in a parameter file as an API key; a public identifier, allowlisted like the three policy ids already were | Fixed in PR #12 the same hour |
| Agent image | Built and pushed to the shared registry (3 minutes 15 seconds) | Derived from the platform's own build-tools image; three pinned, checksummed binaries | None; first execution is the proof |
| Agent pool `meridian-agents` | Created; every pipeline authorized to use it; no agent registered | The placeholder agent needs the jobs, which need the PAT | Platform owner: store the PAT |
| Templates v1.1.0 | Built, reviewed, preview-compiled: all 18 consumers expand to the pool, the default still expands to hosted | Held on purpose: merging before an agent exists fails every consumer run at queue time | Orchestrator, after the proof run |
| Dev teardown and redeploy test | Dry run identical to live inventory; live run refused by the permission classifier before touching anything | Two real blockers in the scripts were found by review and fixed first; the refusal is the hands-off floor, not a defect | Platform owner: allow the two scripts or run the teardown |

Two things the day corrected. The Static Web App deployment task runs Docker underneath, so the frontend could never have moved to the pool as designed; v1.1.0 deploys with the Static Web Apps CLI instead. And the digest check added to base-image promotion only saves a re-run of the same build: every fresh build has a new digest, so a weekly rebuild still re-fires the services by design, and the documentation now says so rather than promising otherwise.

The good numbers: the whole build cost 16 hosted minutes (941 to 957), because everything except one infrastructure run was compiled, dry-run or reviewed rather than executed; and the eight-per-wave duplicate service runs from the third note did not recur, because the sync of the first pull request queued exactly one pipeline.

## Where we are going, and how it is coming out

The path to a pipeline running on the platform's own agent has five steps, and the first is the platform owner's: create a personal access token scoped to Agent Pools (read and manage) and store it in the shared vault, which the agents identity reads and no pipeline ever sees. The orchestrator then merges the prepared flag flip, the infrastructure run creates the two jobs, the placeholder agent registers, the templates repository's own CI runs on the pool as the proof, and the v1.1.0 release moves every consumer. From that point a wave costs zero hosted minutes and any consumer can fall back to the hosted image with one line.

After that milestone the backlog is: the teardown test once the owner unblocks it, two services that read their siblings as existing resources and so depend on deploy order, bringing the agent image under the governed containers pipeline, test and prod environments, Entra app registrations for the services, and a second release manager.

The honest headline is that nothing runs on the new pool yet and one secret only the owner can create stands between here and there. The honest reading is that the day went the way the working agreement intends: two reviewers found five real defects before any of them cost a run (a loop that would have crashed at its own success point, a switch that never read its token, a scale rule in the wrong shape, a deploy task that needs Docker, a proof run that would have failed on a missing PATH entry), and the one run that did fail, failed on a secret scanner doing its job against a GUID. Convergence held; the cost was one afternoon of review rather than a wave.

Three risks. The pool is unproven end to end: the scaler's behaviour against a Microsoft-account organization and the image's runtime dependencies are documented, not observed, and the first job will tell. The token is a long-lived secret in a platform built on workload identity; it is recorded as the one exception, rotates by hand, and any pipeline running on the agent could read it, which is why its scope is limited to agent pools. And the free compute grant has about seven percent headroom at the chosen job size; the cost beyond it is cents per hour, but it is a cost the earlier assessment had modelled at half the size.

The second deliverable, the reference feedback log, now runs to twenty-two sections: a new context on agent hosting, where the reference named the double-run failure and the placeholder-agent rule but not the organization prerequisite that ruled out the managed alternative, and two addenda on triggers and on the Static Web App task.
