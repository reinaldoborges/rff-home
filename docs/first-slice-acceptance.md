# First-slice acceptance matrix

This matrix defines when the first Go RF-DSF implementation is usable as a single-node, end-to-end slice. It is a correctness and recovery gate, not evidence of production readiness. Every scenario below is required.

## Conformance approach

- Assert observable results through the typed API and host persistence port: request acceptance/rejection, execution status and failure data, committed domain state, and notification intent/delivery.
- Keep the suite black-box and reusable across adapters included in the first slice. Use deterministic fakes and fault injection for controlled failures, and run persistence/restart cases against at least one real durable adapter. The adapter choice remains open.
- Control time for expiry, attempt timeouts, deadlines, retry delays, and lease expiry. Use deterministic barriers for races rather than timing sleeps; include an actual process restart for durable recovery.
- A denial or invalid domain request must be explicitly rejected before acceptance, leave committed domain state unchanged, and create no domain side effect or notification. The application may keep its own audit record.

## Domain behavior

| Scenario | Required observable result |
| --- | --- |
| Initialize an entity | The selected initial state's entry hook runs with no previous state; the chosen state becomes current only after successful work. |
| Valid task progression | `Open → InProgress → Done` succeeds; cancellation is allowed before completion. |
| Invalid task progression | Invalid events/guards, including cancellation after completion, are rejected without changing current state or creating side effects. |
| Membership outcomes | Invitation can be accepted, declined, expired, or revoked; acceptance is valid only before the persisted expiry deadline. |
| Expiry boundary | At or after the persisted deadline, expiry wins even if timer delivery is late. |
| Group closure | Pending invitations become revoked with a group-closed reason; closed-group access and further task/membership changes are denied. |
| Terminal history | Terminal Membership records are immutable; a later invitation creates a new record. |

## Requests, concurrency, and retries

| Scenario | Required observable result |
| --- | --- |
| Identical idempotent request | Reuse of the same key and semantic request returns the existing execution and does not create duplicate work. |
| Changed request with same key | A changed operation, machine version, event/input, or notification override is an explicit conflict. |
| Concurrent request acceptance | Snapshot, idempotency mapping, and active-entity reservation are durably created atomically; concurrent matching requests produce one execution, and a storage failure before persistence means not accepted. |
| Competing request | A different request while an execution is active returns busy/conflict. |
| Competing terminal decisions | Membership decisions serialize; the first valid committed transition wins and later incompatible decisions conflict. |
| Retry after handler failure | The selector is not rerun; the same target and pinned policy continue. `Retry` runs only after policy authorization, and retry-hook failure is recorded and handled under that policy. |
| Retry exhaustion | Exhausted attempts or a policy requiring intervention enters `NeedsIntervention` with the old current state intact. |
| Explicit intervention | Authorized retry resumes the same execution; explicit pre-commit abort invokes recovery and leaves the old current state committed. |
| Attempt timeout and deadline | Per-attempt timeout, overall transition deadline, and lease expiry produce distinct handling; no implicit framework retry policy is used. |
| Lease reclaim | After worker loss and lease expiry, the same execution can be reclaimed; a stale fencing token cannot commit. |
| Crash around domain commit | After a durable work-success marker, recovery repeats or reconciles the same idempotent host commit using its execution ID; it does not rerun successful work, and the host-side receipt prevents duplicate state application. |

## Restart and notification recovery

| Scenario | Required observable result |
| --- | --- |
| Accepted but waiting | After process restart, the accepted execution remains discoverable and can run. |
| Worker/process loss during attempt | The durable execution is recovered after lease expiry without selecting a new target or losing its pinned policy. |
| Typed input rehydration | After restart, the execution rehydrates input through its pinned codec or immutable reference and preserves semantic idempotency identity. |
| Active-record schema migration | Adapter migration preserves a pending execution, its idempotency identity, pinned machine/input version, and attempt history so it remains recoverable. |
| Restart during expiry wait | Expiry is decided from the persisted deadline, not the timer or wakeup delivery time. |
| Notification disabled | The execution completes after domain commit without creating a notification handoff. |
| Notification enabled | The selected notification choice is persisted; execution completes on durable handoff, not consumer delivery. |
| Delivery failure | Delivery retries independently and at least once; failure does not alter an Invited Membership or stop its expiry. |
| Handoff repair | After domain commit but before durable handoff, restart recovers `NotificationRepair`; an authorized retry or durable waiver settles it without rolling back domain state. |
| Split-store notification handoff | With transition metadata and domain state in separate stores, the persisted intent and host commit receipt are sufficient to idempotently recreate the outbox handoff after restart; completion waits for durable handoff. |

## Authorization

Use seeded opaque identities for the group owner, an active member, an invited user, and an identity from another group. For every settled authorization rule, include at least one allowed and one denied example, including group isolation, owner-only invitation, active-member task permissions, and assignment only to a current group member. Invited users have no group access. Ownership transfer and active-member removal are excluded until their separate lifecycle decisions are resolved.

## Out of scope

This gate does not require performance or load benchmarks, numeric availability/RTO/RPO targets, multi-node coordination, production identity or notification providers, or production-readiness claims.
