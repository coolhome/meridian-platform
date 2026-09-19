# meridian-approval-service

Owns the approval aggregate: a requester raises a request naming one or more approvers; an
approver approves or rejects; the service publishes `ApprovalRequested` and `ApprovalDecided`
to Storage Queues for `worker-jobs`.

| Endpoint | Auth | Purpose |
| --- | --- | --- |
| `POST /approvals` | any signed-in user | Create a request. Requester cannot be an approver. |
| `GET /approvals` | any signed-in user | List; filters `status`, `mine=requested|approving`, `overdue=true` |
| `GET /approvals/{id}` | any signed-in user | Detail |
| `POST /approvals/{id}/decision` | Approver | Record `approved` / `rejected` with optional comment |
| `GET /health/live`, `/health/ready` | anonymous | Probes |

## Invariants (Domain/ApprovalRequest.cs)

* Title required, at most 200 characters; at least one distinct approver.
* Requester is never an approver (self-approval impossible by construction).
* Only a named approver may decide; each approver decides once; no decisions after final state.
* One rejection rejects; `RequiredApprovals` approvals approve (default 1).

## Configuration

| Key | Values | Notes |
| --- | --- | --- |
| `Storage:Provider` | `InMemory` (default in Development), `Cosmos` | Cosmos uses `Cosmos:AccountEndpoint`, database `meridian`, container `approvals`, managed identity |
| `Messaging:Provider` | `None` (default in Development), `StorageQueue` | `Messaging:QueueServiceUri` with managed identity, or `Messaging:ConnectionString` for Azurite |
| `Meridian:Auth:Mode` | `EntraId`, `Development` | Development is refused outside `ASPNETCORE_ENVIRONMENT=Development` |

## Run locally

```bash
export ASPNETCORE_ENVIRONMENT=Development
dotnet run --project src/Meridian.Approval.Api
curl -X POST http://localhost:5200/approvals -H 'Content-Type: application/json' \
  -H 'X-Meridian-User: alice' -d '{"title":"Laptop","description":"M3","approvers":["bob"]}'
curl -X POST http://localhost:5200/approvals/<id>/decision -H 'Content-Type: application/json' \
  -H 'X-Meridian-User: bob' -H 'X-Meridian-Roles: Approver' -d '{"decision":"approved","comment":"ok"}'
```

With Azurite running, set `Messaging__Provider=StorageQueue` and
`Messaging__ConnectionString=UseDevelopmentStorage=true` to see messages flow to the worker.
