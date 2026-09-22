# ADR 0006: Workload identity everywhere, no stored cloud secrets

**Status:** Accepted, 2026-09-19. Note 2026-09-22: ADR 0008 records one deliberate, scoped
exception — a PAT (Agent Pools Read & manage only) in the `shared` Key Vault for the
`meridian-agents` self-hosted pool's KEDA scale rule and agent registration, forced by the same
Entra-connection gap that keeps Managed DevOps Pools and Entra-identity agent registration out of
reach for this organization. Every other rule in this ADR is unchanged.

## Decision

* Azure DevOps service connections use **workload identity federation** backed by a
  user-assigned managed identity per environment. Created connection first, federated credential
  second, from the issuer and subject the connection returns (never derived by hand).
* Services authenticate to Storage, Cosmos, Key Vault and ACR with **user-assigned managed
  identities** created by platform infrastructure and granted least-privilege data-plane roles.
* Pipeline secrets that cannot be avoided (Static Web Apps deployment token) live in Key Vault
  and reach pipelines through a **Key Vault-linked variable group** per environment.
* `System.AccessToken` is used only to push GitVersion tags on `main`, with
  `persistCredentials: false` on checkout and the token passed through `env:`.
* The GitHub sync workflow uses a PAT scoped to Code (Read & Write) on the Meridian project,
  passed as an `http.extraheader`, never in the remote URL. Replacing it with an Entra workload
  identity service connection is tracked as the first follow-up once that API is stable.
