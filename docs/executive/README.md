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
| 2026-09-22 | Assessment | [Self-hosted capacity: Managed DevOps Pools vs. Container Apps jobs](2026-09-22-self-hosted-capacity-assessment.md) | Container Apps jobs now, not Managed DevOps Pools: `coolhome` is a Microsoft-account-owned org and MDP requires an Entra-connected org, which this org has already been observed to reject; ACA has no such prerequisite and runs on the free self-hosted parallel job the org already has. |
