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
