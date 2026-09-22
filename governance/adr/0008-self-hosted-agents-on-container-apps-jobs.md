# ADR 0008: Self-hosted agents on Container Apps jobs; a PAT in Key Vault as the recorded exception to ADR 0006

**Status:** Proposed, 2026-09-22

## Context

Microsoft-hosted agents cap this organization at 1,800 minutes/month, one parallel job. Handoff-6's
waves ran 941 of 1,800 minutes in one session; a second Microsoft-hosted parallel job costs
$40/month with no minute cap relief below that. The organization already has one self-hosted
parallel job, free and automatic, with unlimited minutes (`docs/executive/2026-09-22-self-hosted-capacity-assessment.md`).

Managed DevOps Pools (MDP) was considered and is out of scope: it requires the Azure DevOps
organization to be connected to Microsoft Entra ID, and `coolhome` is a Microsoft-account-owned
organization that has already rejected an Entra access token (`TF400813`, `docs/handoff.md`,
session two, 2026-09-19). `Microsoft.DevOpsInfrastructure` and `Microsoft.DevCenter` are also
`NotRegistered` on the subscription. Connecting the organization to Entra ID is an org-wide
decision independent of agent hosting (every member re-authenticates); it is not made by this
ADR.

Azure Container Apps (ACA) jobs have no such prerequisite: a KEDA-scaled job polls the agent pool
queue and runs one agent per pending pipeline job. The build-tools base image
(`containers/base-images/build-tools/Dockerfile`: .NET 10 SDK, Node 24, PowerShell, GitVersion,
CycloneDX) already exists and is commented as intended as the base for this agent image; the ACA
job runs that image directly as its own container (`template.containers[].image`), not as a
Pipelines job container referenced from YAML (`resources.containers`) — v1.1.0 uses none of that
mechanism; the pool is where the pipeline's own job runs, full stop.

ACA jobs cannot run Docker inside the container. Every image build already avoids this (`az acr
build` via ACR Tasks, `pipeline-templates/steps/container-build-push.yml`); the one exception was
`container-images.yml`'s hadolint step, which ran `docker run hadolint/hadolint`. This ADR's
template change (v1.1.0) replaces it with the pinned hadolint binary, downloaded with a sha256
check, so `container-images.yml` can run on the pool too.

KEDA's `azure-pipelines` scaler and the agent's own registration both need a PAT scoped to Agent
Pools (Read & manage); this directly contradicts ADR 0006 ("workload identity everywhere, no
stored cloud secrets"). The alternatives Learn documents (service principal, Entra device code
registration) are themselves Entra-identity flows, foreclosed by the same organization-level gap
that rules out MDP. This ADR records the PAT as a deliberate, scoped exception rather than
re-opening ADR 0006.

## Decision

* **Pool**: a single self-hosted agent pool named `meridian-agents`, backed by two Azure Container
  Apps jobs in the `shared` environment, defined in `container-apps-jobs.bicep`: `caj-mrd-shared-agent`
  (event-driven, KEDA scale rule against the pool's job queue, `minExecutions: 0`,
  `maxExecutions: 1`, `parallelism: 1`) and `caj-mrd-shared-agent-placeholder` (manual trigger, run
  by hand to seed the placeholder agent below). Both at 2 vCPU / 4 GiB (Consumption profile; ADR
  0007's minimal-cost posture applies otherwise). One agent at a time, matching today's
  Microsoft-hosted parallelism; a second concurrent job is a $15/month self-hosted parallel-job
  purchase, not a code change.
* **Agent image**: derived from `base/build-tools:10.0` (Azure CLI, Bicep, jq, hadolint, and the
  Azure Pipelines agent added on top), and run directly as each job's own container image
  (`template.containers[].image` on both `caj-mrd-shared-agent` and its placeholder) — not
  referenced from pipeline YAML as a Pipelines job container (`resources.containers`); v1.1.0 uses
  none of that mechanism. Building and publishing the image is platform-dev and containers-repo
  work, tracked separately from this ADR; this ADR fixes the pool name and the template contract
  that targets it.
* **Placeholder agent**: the pool must never scale to zero agents from empty, only from an idle
  registered agent. Running `caj-mrd-shared-agent-placeholder` manually (`AZP_PLACEHOLDER=1`) keeps
  one agent registered so the KEDA scaler has something to route the first real job to; without it,
  Pipelines that use the pool fail at queue time (Microsoft Learn: "Pipelines that use the agent
  pool fail when there's no placeholder agent"), not merely delay. The placeholder agent must never
  be deleted without immediately replacing it.
* **PAT**: scoped to Agent Pools (Read & manage) only, held as the Container Apps secret
  `azdo-agent-pat` on both jobs, bound by Key Vault reference through the `id-mrd-shared-agents`
  user-assigned identity. It is never read by a pipeline or exposed through a variable group — the
  jobs resolve it directly from Key Vault at container start, the same way any other Container Apps
  secret-by-reference works. Rotation: manual, tracked as a recurring platform-engineering task (no
  automated rotation exists yet); updating the Key Vault secret is sufficient, since both jobs
  resolve the reference fresh on their next execution. Readable only by `id-mrd-shared-agents` and
  Platform Engineering; never a build-time secret exposed to consumer pipelines.
* **Consumer opt-in**: `pipeline-templates` v1.1.0 adds a compile-time `agentPool` parameter
  (`hosted` default, `platform` opt-in) to all four extends templates and every job template that
  declares a `pool:`. `pipeline-templates`' own CI (`pipeline-templates-ci`) moves to the pool
  unconditionally as the proof run, landing only once the pool and its placeholder agent exist.
  Every other consumer then opts in with its own pin bump to v1.1.0, in the same wave (ADR 0002:
  the boundary check enforces one `templatesRef` for every consumer, so adoption is not staggered
  per consumer even though the parameter itself allows a per-consumer rollback).
* **Rollback**: `agentPool: hosted` on any consumer reverts that consumer to the Microsoft-hosted
  pool at the next run, no template change required.

## Consequences

* Docker-in-container jobs cannot run on this pool; the templates have none left as of v1.1.0, and
  a `preBuildSteps` allow-list addition that needed Docker would have to stay on `agentPool:
  hosted` or add a non-Docker equivalent.
* One agent at a time: waves still queue sequentially, as they do today on the single
  Microsoft-hosted parallel job. Raising concurrency is a purchase ($15/month/job), not a redesign.
* A stored secret (the PAT) exists where none did before; it is the one recorded, scoped exception
  to ADR 0006, confined to Agent Pools (Read & manage), bound to the two Container Apps jobs as a
  Key Vault-referenced secret through `id-mrd-shared-agents`, and never surfaced to a pipeline or a
  variable group.
* Losing the placeholder agent is an availability incident for every pool-`platform` consumer, not
  a silent degradation: per Microsoft Learn, pipelines that use the pool **fail at queue time**
  with no placeholder agent registered, they do not simply wait. Recovery is a single manual run of
  `caj-mrd-shared-agent-placeholder`, not a redeploy.
* Cost: at 2 vCPU / 4 GiB per job execution, this platform's measured usage
  (`docs/executive/2026-09-22-self-hosted-capacity-assessment.md`) scales to roughly 168,000
  vCPU-seconds and 336,000 GiB-seconds per month — against the Container Apps Consumption free
  grant of 180,000 vCPU-seconds and 360,000 GiB-seconds, that leaves little headroom, and volume
  above the assessment's baseline bills at roughly $0.17/hour beyond the grant. ADR 0007 accepts
  that cost over the alternative (a smaller job size, slower builds) at the parallelism-1 scale
  this pool runs at; the self-hosted parallel job itself is free up to the first one regardless of
  job size.
