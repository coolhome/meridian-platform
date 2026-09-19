# meridian-observability

SRE-owned alerting, availability tests, workbooks and SLOs, deployed per environment into
`rg-mrd-<env>-platform` next to the shared Log Analytics workspace and Application Insights.

| Path | Contents |
| --- | --- |
| `alerts/main.bicep` | Action group, per-service metric alerts (replica restarts), per-service log alerts (5xx rate, exception spike), availability tests on `/health/live`, the platform workbook |
| `alerts/params/<env>.bicepparam` | Thresholds and notification targets per environment |
| `workbooks/platform-overview.workbook.json` | Requests, failures, latency, queue depth per service |
| `kql/` | Saved queries used by alerts and by humans during incidents |
| `slo/slos.yaml` | SLO definitions and error budgets that the alerts implement |

The pipeline extends `infrastructure.yml@templates` at resource-group scope, so the same
what-if -> approve -> deploy flow applies to alert changes as to infrastructure.
