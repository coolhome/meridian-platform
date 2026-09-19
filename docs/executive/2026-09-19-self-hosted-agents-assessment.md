# Assessment: self-hosted agents as Container Apps jobs scaled by KEDA, 2026-09-19

| | |
| --- | --- |
| Audience | Leadership readers who know what a CI/CD platform is but have not followed the day-to-day |
| Question | What if the pipelines ran on self-hosted Azure Pipelines agents hosted as Azure Container Apps jobs, scaled by KEDA from the agent pool, instead of the single Microsoft-hosted agent? |
| Verdict | Fits this platform well and the numbers say it is cheap. It solves throughput and minutes, not any of the five current failures, so schedule it as the first initiative after the first green dev deploy. |
| Evidence as of | 2026-09-19 19:30 UTC. Hosted usage from the Azure DevOps resource-usage API; pool and template facts from the repo; Microsoft Learn: Container Apps jobs CI/CD tutorial, scale rules, billing, parallel jobs |

## What it is

Microsoft documents this exact pattern: an event-driven Container Apps job whose KEDA rule polls an Azure DevOps agent pool. Each pending pipeline job starts one container that registers an agent, runs that single job, and exits. You pay per second of execution and nothing when idle.

## What it buys here

The hosted agent budget is the real constraint, and today's waves show it.

| Capacity | Hosted today | Self-hosted on Container Apps |
| --- | --- | --- |
| Minutes used this month | 498 of 1,800 | No monthly limit |
| Parallel jobs, free tier | 1 | 1 |
| Extra parallel jobs | Paid add-on | Paid add-on, list price about $15 a month each |
| Container Apps free grant per month | n/a | 180,000 vCPU-seconds and 360,000 GiB-seconds |
| Waves that fit in that grant, at ten jobs of eight minutes on 2 vCPU | n/a | About 18 |

Two things follow from that table. First, at the current rate the hosted minutes run out in roughly three more days of this kind of work, so unlimited minutes matters more than it looks. Second, KEDA can launch five agents, but Azure DevOps admits only as many concurrent jobs as the organisation has parallel jobs. Without buying one or two extra self-hosted parallel jobs, the gain is unlimited minutes and shorter jobs, not concurrency. Shorter jobs are still real: every tool the pipelines install at run time today can be baked into the agent image, and the existing build-tools image is the natural base for it.

## What it changes, and the three catches

* **A PAT enters a workload-identity-everywhere design.** The scale rule for the azure-pipelines scaler accepts only secrets. Managed identity on scale rules covers Azure Queue, Service Bus and Event Hubs, not this one. Agent registration by service principal exists, but the coolhome organisation is Microsoft-account owned and already rejected Entra tokens, so registration needs a PAT too. That is the first long-lived secret in the platform. It expires within a year, someone rotates it, and it belongs in Key Vault referenced by the job's managed identity. This deserves an ADR because it contradicts ADR 0006 on purpose.
* **No Docker inside Container Apps jobs.** The image builds are safe because they already use ACR Tasks. The one casualty is the hadolint step, which runs through `docker run` today and must switch to the hadolint binary. Trivy image scans read the registry directly and should be unaffected.
* **The pool becomes a template concern.** All four extends templates declare a hosted image in six places. Switching to a named self-hosted pool is a new template tag, a re-pin in every consumer, and a bootstrap change so each pipeline is authorised on the pool. Keep the containers pipeline on the hosted pool as a fallback, so a broken agent image can still be rebuilt.

Smaller points: the pool needs a one-time offline placeholder agent or every pipeline fails with no agents available. The job's replica timeout must exceed the longest job, and its retry limit must be zero so Container Apps never re-runs a failed pipeline job. It should live in a consumption-only Container Apps environment in the shared footprint, not inside the dev environment, so prod deployments never execute inside the dev boundary. Idle cost of that environment is zero.

## What it does not do

None of the five wave failures touch the agent. It adds roughly one session of work before the first deployment and gives the reference feedback log a new context, which is in keeping with the platform's purpose.

## Decisions for the platform owner

1. Whether to buy one or two extra self-hosted parallel jobs, which is what turns this from unlimited minutes into real parallelism.
2. Whether a rotated PAT is an acceptable exception to the workload-identity rule, which decides if this fits the governance story or undermines it.

## Recommendation

Do it, after the first green wave, scoped as: agent image derived from build-tools, one Container Apps job in shared, PAT in Key Vault, a template tag that names the pool, the hadolint swap, and ADR 0008 recording the exception.
