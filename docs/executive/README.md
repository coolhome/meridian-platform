# Executive notes

Dated notes written for leadership readers who know what a CI/CD platform is but have not
followed the day-to-day. Two kinds:

* **Narrative**: where we were, where we are, where we are going, and how it is coming out.
  Each one starts from the previous narrative, so the story accumulates instead of being
  rewritten.
* **Assessment**: a "what if we did X" question answered with verified numbers, the catches,
  what it does not fix, and the decisions that belong to the platform owner.

Regenerate or add one with the `/exec-narrative` project skill (`.claude/skills/exec-narrative`).
It reads the handoff docs, git history, memory and the live Azure Pipelines state before writing,
and it verifies every failure to the log line rather than trusting the last handoff's attribution.

## Index

| Date | Kind | Note | One line |
| --- | --- | --- | --- |
| 2026-09-19 | Narrative | [Rollout narrative](2026-09-19-rollout-narrative.md) | Platform fully wired in three sessions; the v1.0.6 wave was the first to run every pipeline to a real outcome; five distinct first-deploy causes diagnosed; nothing deployed yet. |
| 2026-09-19 | Assessment | [Self-hosted agents on Container Apps jobs](2026-09-19-self-hosted-agents-assessment.md) | Fits well and is cheap; fixes throughput and minutes, not the five current failures; do it after the first green dev deploy; a PAT and the no-Docker rule are the catches. |
| 2026-09-19 | Narrative | [Rollout narrative, second note](2026-09-19-rollout-narrative-2.md) | Verification pass over the v1.0.6 wave: four of five causes confirmed to the log line, a sixth found (deploy stages are not gated on Build in the node-spa path), both human-only blockers still open, minutes at 498 of 1800. |
| 2026-09-21 | Narrative | [Rollout narrative, third note](2026-09-21-rollout-narrative.md) | The platform deployed: the v1.0.9 wave took nine of ten pipelines green and the four services run in dev with healthy endpoints; every service had been running three times per wave, fixed; postscript: the owner's role grant landed and infrastructure went green the same hour, all eleven pipelines green, minutes at 941 of 1800. |
| 2026-09-22 | Narrative | [Rollout narrative, fourth note](2026-09-22-rollout-narrative.md) | Dev unchanged and green; the self-hosted agent pool's shared half is deployed (environment, vault, identity, image, authorized pool), templates v1.1.0 is built and preview-compiled and held until an agent exists; one owner action (the agent PAT) gates the first job on the pool; the day cost 16 hosted minutes; the teardown test is blocked by the permission classifier. |
| 2026-09-22 | Assessment | [Self-hosted capacity: Managed DevOps Pools vs. Container Apps jobs](2026-09-22-self-hosted-capacity-assessment.md) | Container Apps jobs now, not Managed DevOps Pools: `coolhome` is a Microsoft-account-owned org and MDP requires an Entra-connected org, which this org has already been observed to reject; ACA has no such prerequisite and runs on the free self-hosted parallel job the org already has. |
| 2026-09-23 | Narrative | [Rollout narrative, fifth note](2026-09-23-rollout-narrative.md) | The agent pool is live and its proof run went green, but the templates v1.1.0 wave that moved every consumer onto it failed 5 of 6 code-building pipelines on their first real job: `GitVersion` runs before `UseDotNet@2` and the pool's agent reports zero installed .NET SDKs, a defect no preview compile could catch; shared approval also hit a second classifier refusal this session. |
| 2026-09-23 | Narrative | [Rollout narrative, sixth note](2026-09-23-rollout-narrative-2.md) | Cause confirmed: `dotnet-runtime-8.0` hid the SDK; the first fix attempt replaced the 10.0 muxer with the 8.0 one, caught by the reviewer's podman check before it shipped; image 1.0.1 verified in ACR and merged, 4 of 5 re-run pipelines green end to end with `GitVersion` confirmed passing, the 5th still running; a run-list watcher error, not a trigger defect, caused one duplicate infrastructure run; the hosted-minute meter moved another 6 minutes with zero hosted-pool jobs in evidence, still unattributed. |
