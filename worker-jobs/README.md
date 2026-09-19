# meridian-worker-jobs

Background processing for approvals, packaged as a Container App (no ingress) that KEDA
scales on the `approval-requested` queue length.

| Job | Trigger | What it does |
| --- | --- | --- |
| `QueueProcessor<ApprovalRequested>` | Storage Queue `approval-requested` | Notifies approvers (`INotifier`, log-based here), writes an `ApprovalAuditEntry` |
| `QueueProcessor<ApprovalDecided>` | Storage Queue `approval-decided` | Notifies the requester, writes an audit entry |
| `EscalationJob` | Timer (`Escalation:IntervalMinutes`) | Asks approval-service for overdue requests and writes escalation audit entries |

## Message handling rules (`Messaging/MessageDispatcher.cs`)

* Envelope header is peeked first; unknown `messageType` or `schemaVersion` -> poison queue.
* `DequeueCount` above `Messaging:MaxDequeueCount` (default 5) -> poison queue.
* Handler exception -> message left invisible until the visibility timeout expires, then retried.
* Successful handling -> message deleted; `MessageHandled` custom event with lag telemetry.

## Calling approval-service

`ApprovalApiClient` authenticates with the worker's managed identity
(`DefaultAzureCredential`, scope `Downstream:Approvals:Scope`) in `EntraId` mode, or sends
`X-Meridian-User: worker-jobs` / `X-Meridian-Roles: Service` in `Development` mode.

## Run locally (Azurite)

```bash
export ASPNETCORE_ENVIRONMENT=Development
export Messaging__ConnectionString="UseDevelopmentStorage=true"
dotnet run --project src/Meridian.Worker      # http://localhost:5300/health/live
```
