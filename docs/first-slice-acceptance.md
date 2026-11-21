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
| Membership outcomes | Invitation can be accepted, declined, expired, or revoked; acceptance is valid only before the persisted expiry deadline. Owner removal of an Active Membership produces the distinct terminal outcome `Removed`. |
| Expiry boundary | At or after the persisted deadline, expiry wins even if timer delivery is late. |
| Group closure | Pending invitations become revoked with a group-closed reason; closed-group access and further task/membership changes are denied. |
| Removal with assigned tasks | Owner removal is rejected while a task remains assigned to the member; the membership remains Active and access is unchanged. |
| Active membership removal | After assigned tasks are unassigned or reassigned, owner removal ends group access atomically, retains the Removed Membership and historical task references, and records the owner and time in the application-owned business audit. |
| Ownership transfer | The current owner transfers to another Active member of the same open group without recipient acceptance; both memberships remain Active, task assignments are unchanged, owner permissions switch atomically, and the business audit records actor, former owner, new owner, and time. No notification is required. |
| Invalid ownership transfer | A non-owner, self-transfer, invited or removed recipient, cross-group recipient, or transfer in a closed group is rejected without changing ownership or creating a successful outcome. |
| Ownership transfer replay | An authenticated original actor's identical actor-and-group-scoped key returns the recorded outcome without another transfer, even after losing ownership, membership, or group access. Changed parameters conflict. A crash cannot persist the transfer without its audit and idempotency outcome. |
| Ownership transfer races | Deterministic races with another transfer, recipient removal, and group closure serialize at the authoritative domain boundary. A successful transfer has exactly one owner; no removal of the current owner or change to a closed group commits. |
| Previously accepted owner work | A former owner's validly accepted work is not deauthorized by transfer, but its commit rechecks current domain invariants. A removal of the new owner or a change to a closed group is rejected; new owner-only requests from the former owner are denied. |
| Terminal history | Terminal Membership records are immutable; a later invitation creates a new record. |
| Reinvite after removal | Re-inviting a removed user creates a new Membership record; the prior Removed record remains unchanged and only one Invited or Active membership exists per group/user. |

## Requests, concurrency, and retries

| Scenario | Required observable result |
| --- | --- |
| Identical idempotent request | Reuse of the same key and semantic request returns the existing execution and does not create duplicate work. |
| Changed request with same key | A changed operation, machine version, event/input, or notification override is an explicit conflict. |
| Concurrent request acceptance | Snapshot, idempotency mapping, and active-entity reservation are durably created atomically; concurrent matching requests produce one execution, and a storage failure before persistence means not accepted. |
| Competing request | A different request while an execution is active returns busy/conflict. |
| Workflow and external-input ingress | A command starts a workflow; external events and human decisions enter through typed Go APIs and are durably deduplicated. Repeating an input with the same identity and semantic payload returns its prior outcome; changed payload with the same identity conflicts. |
| Timer ingress and recovery | The runtime persists and fires timers. After delay or restart, expiry and other deadline behavior follow the persisted deadline, not timer delivery time. |
| Competing terminal decisions | Membership decisions serialize; the first valid committed transition wins and later incompatible decisions conflict. |
| Worker activity identity | Re-delivery of the same hook invocation reuses its stable transition/hook/retry-cycle identity and idempotency key; each started attempt has a distinct attempt number and activity-lease generation. |
| Stale worker report | After an activity lease is reclaimed with a newer generation, a late renewal or result from the prior worker is rejected; it cannot advance the transition or commit domain state. |
| Retry after handler failure | The selector is not rerun; the same target and pinned policy continue. `Retry` runs only after policy authorization, and retry-hook failure is recorded and handled under that policy. |
| Retry exhaustion | Exhausted attempts or a policy requiring intervention enters `NeedsIntervention` with the old current state intact. |
| Explicit intervention | Authorized retry resumes the same execution; explicit pre-commit abort invokes recovery and leaves the old current state committed. |
| Operator control phase gates | Inspection can read any execution; retry is accepted from `NeedsIntervention`, pre-commit abort from `NeedsIntervention` or `CommitRejected`, and notification retry or waiver only from `NotificationRepair`. `CommitRejected` cannot retry or migrate. The runtime rejects invalid-phase control requests without changing execution or domain state. |
| Attempt timeout and deadline | Per-attempt timeout, overall transition deadline, and lease expiry produce distinct handling; no implicit framework retry policy is used. |
| Worker loss with unknown outcome | A started attempt whose worker disappears consumes an attempt under the pinned transition policy and may be redelivered with the same logical identity; a claim lost before start consumes no attempt. |
| Lease reclaim | After worker loss and lease expiry, the same execution can be reclaimed; a stale fencing token cannot commit. |
| Crash around domain commit | After a durable work-success marker, recovery repeats or reconciles the same idempotent host commit using its execution ID; it does not rerun successful work, and the host-side receipt prevents duplicate state application. |
| Definitive commit rejection | After successful hook work, a source mismatch or failed current invariant yields a durable fenced rejection receipt and `CommitRejected`, without domain mutation or notification intent. Later invariant changes do not make that operation succeed; the reservation remains held until authorized abort and recovery are durably complete. Possible external effects remain visible. |
| Rejection reconciliation | A lost rejection response or restart reconciles the same receipt without rerunning the successful hook or changing the result, including after domain conditions change. A lost success response similarly remains successful. Unknown transport/storage outcomes and stale fences are not recorded as definitive rejection; stale fences cannot write a rejection receipt. |
| Rejected source drift | If authoritative state differs from the accepted source, rejection and subsequent abort leave that authoritative state intact rather than restoring the snapshot. |

## Restart and notification recovery

| Scenario | Required observable result |
| --- | --- |
| Accepted but waiting | After process restart, the accepted execution remains discoverable and can run. |
| Worker/process loss during attempt | The durable execution is recovered after lease expiry without selecting a new target or losing its pinned policy. |
| Coordinator reconciliation | Dropping a transient wakeup does not strand a due execution; the coordinator discovers and advances it from persisted state after polling or restart. |
| Graceful worker shutdown | The worker stops new claims, drains while renewing active leases until its shutdown deadline, then cancels and stops renewal; the coordinator recovers after lease expiry without accepting a fabricated success. |
| Worker health and capacity | Worker heartbeat, ready/draining state, and capacity are observable separately from coordinator/persistence health; stale workers are unavailable, and zero available workers is degraded capacity while durable acceptance remains possible. |
| Typed input rehydration | After restart, the execution rehydrates input through its pinned codec or immutable reference and preserves semantic idempotency identity. |
| Active-record schema migration | Adapter migration preserves a pending execution, its idempotency identity, pinned machine/input version, and attempt history so it remains recoverable. |
| Concurrent behavior versions | Two versions of a machine and codec coexist; existing work uses its pinned hooks and classifier, new work can use the new version, and duplicate identity/version registrations are rejected. |
| Unsupported behavior | An unavailable machine, hook, classifier, codec, or incompatible state value blocks only the affected execution, preserves its phase and reservation, and exposes safe diagnostics; compatible work continues. Restoring compatibility clears the block without bypassing phase gates or extending deadlines. |
| Unsupported record schema | An adapter unable to read or migrate its record schema fails initialization explicitly and makes no writes to the store. |
| Explicit execution migration | An authorized migration of quiesced pre-commit work atomically records the converted snapshot and history, validates destination compatibility, and preserves original request identity, reservation, attempt counts/history, deadlines, notification choice, operation identities, and policy meaning without rerunning selection. Unauthorized requests and requests in commit-pending, notification, or abort-recovery phases leave execution unchanged. |
| Migration crash and deduplication | A crash or validation failure leaves no partial migrated snapshot; an identical migration-request ID returns its recorded outcome, changed parameters conflict, and a stale worker report cannot advance migrated work. A started unknown attempt is counted before migration. |
| Domain migration coordination | The host verifies the migrated source against authoritative domain state and prevents conflicting changes; failed verification blocks execution. Separate stores are not treated as an atomic migration. |
| Idempotency with unavailable versions | Original request identity remains authoritative after migration; when semantic equality cannot be verified, including for terminal records, the request fails explicitly without creating another execution. |
| Restart during expiry wait | Expiry is decided from the persisted deadline, not the timer or wakeup delivery time. |
| Notification disabled | The execution completes after domain commit without creating a notification handoff. |
| Notification enabled | The selected notification choice is persisted; execution completes on durable handoff, not consumer delivery. |
| Notification worker retry | A durable notification intent is delivered as its own worker activity with stable identity/idempotency and an independent delivery retry lifecycle; delivery retries do not rerun transition hooks or change the committed domain state. |
| Delivery failure | Delivery retries independently and at least once; failure does not alter an Invited Membership or stop its expiry. |
| Handoff repair | After domain commit but before durable handoff, restart recovers `NotificationRepair`; an authorized retry or durable waiver settles it without rolling back domain state. |
| Split-store notification handoff | With transition metadata and domain state in separate stores, the persisted intent and host commit receipt are sufficient to idempotently recreate the outbox handoff after restart; completion waits for durable handoff. |

## Authorization

Use seeded opaque identities for the group owner, an active member, an invited user, an identity from another group, and a test-only operator. The operator can inspect/list fixture executions and request phase-valid controls, but has no task-manager permissions; task-manager roles do not by themselves grant operator controls. The fixture authorizes these operations and records the actor and action in its application-owned audit. The development CLI uses this same fixture policy and remains local/test-only.

For every settled authorization rule, include at least one allowed and one denied example, including group isolation, owner-only invitation, active-member removal and ownership transfer, active-member task permissions, assignment only to a current group member, and operator controls. Invited and removed users have no group access; an authenticated original actor's read-only transfer replay is the exception specified above.

## Out of scope

This gate does not require performance or load benchmarks, numeric availability/RTO/RPO targets, multi-node coordination, production identity or notification providers, or production-readiness claims.
