# RF-DSF

Working name: **RF-DSF (RF Distributed Systems Framework)**. This tree describes logical areas, not repository or Go package boundaries. See [the architecture baseline](../architecture.md) for the agreed scope and deferred decisions.

- **Framework**
  - Domain modeling: optional Go-native patterns for types, invariants, validation, and transitions; no mandatory DDD layering or ORM.
  - Persistence: optional application-owned ports and patterns; applications own domain data and choose its store.
  - Security
    - Cryptography: safe boundaries around reviewed cryptographic operations; concrete API surface deferred.
    - Key Management: key custody/lifecycle interfaces; external adapters deferred.
    - Authentication: optional mechanisms using crypto/key-management ports; no required account system or identity provider.
    - Authorization: application-owned domain permissions plus framework workload-level checks.
  - FSM (Finite State Machine)
    - Flat, deterministic states, events, guards, and transitions.
    - Application-defined validators and transition logic.
    - No persistence adapter instance; execution persistence belongs to the runtime.
- **Infrastructure**
  - Workflow Runtime: persists orchestration progress, schedules durable timers, invokes activities, and applies application-supplied retry and timeout policies.
  - Worker: claims and executes leased activities; delivery is at least once and handlers must be idempotent.
  - Service Manager: single-node coordinator for the first implementation; multi-node coordination is a future design.
  - Triggers and ingress: commands, external events, and timers; HTTP, event receiver, scheduled-start, and a small development CLI are adapters. MCP is deferred.
  - Pub/Sub: in-memory wakeups only in the first implementation; polling/reconciliation recovers work after notification loss or restart.
  - Persistence: the host application injects transition persistence; SQLite may be the first adapter. Application domain persistence remains application-owned.
  - Operations: structured logs, health/readiness checks, and basic workflow/worker metrics.
  - Candidate adapters (not MVP commitments): MySQL, PostgreSQL, object storage, cache, secrets stores, cloud connectors, and dedicated brokers.
- **Test Suite**
  - A small multi-user task-manager domain: groups, lifecycle-based memberships (including the Invited phase), owners, and tasks.
  - Fixture and infrastructure tests for permissions, duplicate inputs, retries, expiry, restart/recovery, and failure handling.
  - Scripts and a development CLI for exercising fixture workflows.

## First implementation scope

The first Go implementation is a usable single-node baseline: the host application injects transition persistence (SQLite may be the first adapter); the in-memory queue is a transient wakeup path; polling/reconciliation restores progress after queue loss or process restart. It includes typed state-machine and worker/activity contracts plus the task-manager fixture. Public APIs remain experimental until adopters validate them.

## Explicitly deferred

- Multi-node service-manager coordination and production control plane.
- Production identity providers, MFA, SPIFFE, concrete crypto APIs, and KMS adapters.
- MCP, cloud-specific adapters, and additional persistence/messaging backends.
- Permanent project name, distribution/license, implementation repository/package layout, and numeric availability/RTO/RPO targets.
- Selection of a real first-adopter workflow; choose it before freezing APIs.