# ADR 0005: Storage Queues for domain events (Service Bus deferred)

**Status:** Accepted, 2026-09-19

## Context

The approval workflow emits three event kinds (`ApprovalRequested`, `ApprovalDecided`, audit
entries) consumed by one worker. Ordering across approvals is not required; at-least-once
delivery with idempotent handlers is.

## Decision

Use Azure Storage Queues with base64 JSON envelopes and a poison queue per source queue.
Queue names are owned by `platform-libraries/queues.json` and created by that repo's pipeline
against the platform storage account. The worker scales with a KEDA `azure-queue` rule.

## Consequences

* No topics or subscriptions; a second consumer means a second queue and a fan-out step. That
  is the trigger to revisit Service Bus.
* Envelope carries `messageType` and `schemaVersion` so the same queue can carry v2 payloads.
