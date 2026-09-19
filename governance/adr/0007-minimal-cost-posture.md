# ADR 0007: Minimal cost posture in every environment

**Status:** Accepted, 2026-09-19

## Context

The platform exists to exercise Azure DevOps and Git governance, not to serve production load.
Every gate (approvals, locks, branch control, required templates, canary rollout) is free; every
recurring cost is a resource size or redundancy choice. We want the governance to behave like
production while the bill behaves like a sandbox.

## Decision

All environments, including `prod`, use the minimal-cost parameters:

| Area | Setting |
| --- | --- |
| Container Apps | `minReplicas: 0` (scale to zero), `maxReplicas: 2`, 0.25 vCPU / 0.5 GiB, Consumption profile, no zone redundancy |
| Storage | `Standard_LRS`, no replication |
| Container registry | `Basic` SKU, single shared registry |
| Cosmos DB | serverless, single region, no zone redundancy, 7-day continuous backup (free tier) |
| Log Analytics / App Insights | 30-day retention (free window), 1 GB/day cap |
| Static Web Apps | `Free` SKU in every environment |
| Availability tests | one probe (`app-backend`), one location, every 15 minutes |
| Log alerts | evaluated every 15 minutes |

Kept at production values because they are nearly free and painful to retrofit: Key Vault purge
protection and soft delete, Cosmos continuous backup, managed identities and RBAC, policy
assignments, diagnostics to Log Analytics.

## Consequences

* Estimated idle cost for `shared` + `dev` + `test` + `prod` is roughly 60 to 80 USD per month,
  dominated by log ingestion and the Cosmos backup minimum. Individual environments can be
  deleted and recreated from the pipelines at will.
* First request after idle pays a cold start of a few seconds; the canary in `prod` handles the
  "no active revision" case by routing 100 percent to the new revision.
* No SLA above single-instance defaults. `observability/slo/slos.yaml` objectives are
  aspirational under this posture.
* Scaling up is a parameter change per environment: `minReplicas`, `cpu`, `memory` in each
  service's `infra/params/<env>.bicepparam`; `storageSkuName`, `containerRegistrySku`,
  `logRetentionInDays`, `logDailyQuotaGb` in `platform-infrastructure/bicep/params/<env>.bicepparam`;
  `skuName` in `app-frontend/infra/params/<env>.bicepparam`. Each is a normal PR through the
  same gates.
