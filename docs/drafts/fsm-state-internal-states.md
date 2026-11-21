# FSM and transition execution

This draft refines the FSM boundary in the [architecture baseline](../architecture.md). A domain FSM remains deterministic; the internal states below describe the durable execution of one requested state change, not additional domain states.

## Domain state machine

- Each entity has exactly one committed current state.
- The application defines typed states and event/guard-driven transitions. A pure application selector chooses a valid target from the committed state, event, and prepared immutable input; invalid requests are rejected before acceptance.
- A machine has one or more declared initial states, and each creation request selects exactly one. A one-state machine is valid. Terminal states are optional; an application-declared terminal state has no ordinary outgoing transitions unless reopening is explicitly modeled.
- A different state-change request cannot run while one is active for the entity. It receives a busy/conflict result; a repeated request with the same idempotency key returns the existing result.

### Typed Go contract

The first Go API is generic over application-owned `EntityID`, `StateID`, `Event`, and `Input` types. `EntityID` and `StateID` are comparable; event and input types are otherwise unconstrained. Each machine has a stable application-owned ID and explicit version, with handlers registered by target state ID. Multiple versions of the same machine and input codec may be registered concurrently; duplicate registrations for the same identity and version are rejected.

The ordinary selector is synchronous and side-effect-free. It receives the committed source state, event, and input prepared by the application; it does not receive `context.Context` or perform I/O. A separate initial selector chooses the initial state without a synthetic event. Each selector returns a typed selection containing the target state, effective execution policy, and notification default. The machine version pins selector, target-state hook, and failure-classification behavior; behavior-changing replacements use a new version. The framework validates that the selected target is registered.

Each target state implements a typed handler contract with distinct `Enter`, `Transition`, `Retry`, and `Recover` hooks. Hooks receive an immutable execution context containing entity identity, `previous` (absent only during initialization), `next`, event (absent during initialization), accepted input or immutable reference, idempotency key, and attempt metadata, plus Go `context.Context`. Retry and recovery hooks also receive the persisted failure envelope. Unused hooks use an explicit no-op helper.

The host supplies typed persistence and commit operations. A handler reports work success but does not mutate a framework-owned entity. The host commits `current = next` only after successful work, checking the expected `previous` and fencing token. Where state and execution share a store, commit them atomically; across stores, make the commit idempotent and recoverable.

Acceptance uses separate initialization and transition operations and returns the persisted execution plus an error only when the request was not accepted. The typed execution status is one of `Waiting`, `Running`, `Notifying`, `NotificationRepair`, `NeedsIntervention`, `Aborting`, `Complete`, or `Aborted`; domain state IDs remain separate. A post-acceptance failure is recorded on the execution, not returned as an acceptance error.

Every request has an idempotency key and typed input or immutable reference. For a given entity, key reuse returns the prior execution only when operation kind, machine ID and version, event/input, and notification override match; otherwise it conflicts. If semantic equality cannot be verified because the necessary codec or identity representation is unavailable, return an explicit compatibility error rather than guessing or creating work, including for retained terminal records. Notification override is tri-state: inherit the selected default, enable, or disable.

The selected, versioned execution policy is serializable and persisted with the execution. `MaxAttempts` includes the first attempt; per-attempt timeout, overall transition deadline, retry-delay schedule, and lease expiry are distinct. There are no implicit framework retry defaults. A versioned application mapper converts a live Go error into a safe serializable failure envelope and a disposition. Persist both with the execution; replay only the envelope to later hooks, never the raw error.

Explicit, phase-checked controls may retry or abort a `NeedsIntervention` execution, and retry or waive a `NotificationRepair` handoff. The application owns authorization for these controls.

## Worker, activity, and coordinator contract

The persisted transition execution remains the durable authority for its state-hook work. Each `Enter`, `Transition`, `Retry`, or `Recover` invocation is dispatched as worker activity within that execution; it does not create a second top-level activity record. The hook receives the immutable typed execution context and returns success or a live Go error. The pinned application failure classifier maps errors to safe persisted failure data. In the first slice, the hook contract has no arbitrary typed result payload and does not expose a general free-standing activity API.

The coordinator reconciles due and recoverable executions from persistence; transient wakeups only reduce latency. It owns and renews the per-entity transition lease, advances the persisted protocol, dispatches hooks, and invokes the host's idempotent fenced commit after successful work. Workers claim and renew separate activity leases, execute the dispatched hook, and report outcomes; they do not commit domain state. The activity lease generation fences claims, renewals, and reports. The per-entity transition generation is distinct and fences the host commit. A report or renewal from a stale activity generation is rejected; an expired transition lease can be reclaimed only with a new per-entity generation.

A logical hook invocation has a stable identity scoped to transition execution, hook kind, and retry cycle where applicable. Redelivery of that invocation reuses its idempotency key; each started worker attempt has its own attempt number and activity-lease generation. The host commit's stable operation ID remains separate and transition-scoped. A started attempt whose outcome is unknown because its worker disappeared consumes an attempt under the pinned transition policy; a claim lost before the attempt starts does not. If work may have succeeded before its result became durable, it can run again, so application side effects remain idempotent. Neither lease fences a downstream system that does not participate in that fencing protocol.

The pinned transition policy governs state-hook attempt limits, retry classification, and timeouts; a second activity retry policy is not layered over those hooks. Notification delivery is different: a durable notification intent is dispatched as its own worker activity, with a stable identity/idempotency key and an independent delivery retry lifecycle. The notification intent remains the source of truth, and consumer delivery does not delay transition completion after durable handoff.

On graceful shutdown, a worker stops claiming new activities and drains current work while renewing its activity leases until the caller-provided shutdown deadline. At that deadline it cancels active work and stops renewing; it does not report fabricated success. After lease expiry, the coordinator recovers the same execution under its pinned policy. Workers report heartbeat, ready/draining state, and capacity. Coordinator/persistence health is distinct from execution capacity; zero available workers is degraded capacity while durable acceptance may continue.

Lease TTLs and renewal intervals, worker-staleness thresholds, and graceful-shutdown deadlines are explicit runtime settings. Their values are deployment and implementation choices, not universal timing guarantees. Expiry is a recovery/reclaim signal, not a domain timeout; per-attempt and overall transition deadlines remain governed by the pinned execution policy.

## Transition execution record

The framework defines a generic transition-execution record and typed persistence port. The host application configures and injects an adapter; the framework does not own the entity schema or store. SQLite may be provided as the first adapter. The application may store transition metadata alongside its entity or in a related store.

Acceptance durably creates the immutable execution snapshot, idempotency mapping, and reservation of the entity's one active execution as one serialized adapter operation. Competing requests cannot create duplicate executions: a matching key returns its existing execution, a changed request with the same key conflicts, and another key while the entity is active receives busy/conflict. Acceptance is returned only after this write succeeds; a storage failure before it is durable means the request was not accepted.

The accepted snapshot includes the source (`previous`), target (`next`), machine ID and version, selected policy, notification choice, idempotency identity, and the minimum input needed for retry. For initialization, `previous` is null. Applications provide a versioned codec with a stable semantic representation or a durable immutable input reference; the framework does not assume arbitrary Go input can be serialized. Persist the codec/reference version and use the same semantic identity for idempotency comparison. Retries rehydrate input under the pinned machine version and do not re-evaluate selectors or guards.

Version the transition-record schema independently from the application machine version. The adapter owns transition-schema migrations; the host owns domain-schema migrations. Migrations preserve active executions, idempotency mappings, and attempt history. Applications keep pinned machine and input-codec behavior available until executions settle, or provide an explicit migration; an in-flight execution is never silently reinterpreted. The first slice retains terminal transition records and idempotency mappings without automatic expiry or deletion.

### Compatibility and explicit execution migration

Resolve each execution against its exact machine ID and version and its pinned codec or reference version, never the newest available version. If a required machine, hook, classifier, codec, or state value is unavailable or incompatible, block the affected execution without changing its protocol phase or releasing its reservation. Record safe diagnostics separately from the phase, including the incompatible component and version; inspection must not expose input secrets. Other supported executions continue. A control remains subject to its normal phase gate and requires all components needed for that action; it cannot bypass compatibility checks.

After the host restores the missing behavior, revalidation clears the compatibility block. This does not authorize an intervention retry or notification waiver. Leases and deadlines continue to advance while blocked, and normal deadline and retry rules apply when execution can proceed. If the adapter cannot safely read or migrate the transition-record schema, it fails initialization explicitly without writing to that store.

The host may authorize and audit a per-execution migration before the durable work-success/commit-pending marker. Commit-pending, notification, and abort-recovery phases cannot be migrated and must settle under their original version. Drain or fence outstanding attempts first; reject stale reports. A started attempt with an unknown outcome is recorded and counted under the existing policy before migration. Fencing does not stop or undo external effects, which the application must account for.

An application-supplied, side-effect-free migrator converts the versioned persisted representation; it may translate machine/version, source/target, input, and policy representation without rerunning selection. The runtime validates destination machine, relevant hooks and classifier, codec, state values, and policy. A fenced adapter operation atomically persists the complete new snapshot and migration history. A crash or validation failure cannot leave a partial snapshot; failed validation leaves the execution blocked with a reason. A stable migration-request ID returns the recorded outcome for identical execution and parameters and conflicts on different parameters.

Preserve the original accepted request data for idempotency comparisons, execution and operation/activity identities, reservation, attempt history and counts, deadlines, notification choice, and effective policy meaning. Migration cannot silently reset attempts, extend deadlines, or change retry policy. The host coordinates domain-schema cutover, prevents conflicting domain changes, and verifies the migrated source against authoritative domain state, including absence for initialization. If verification fails, keep execution blocked. The runtime migrates its record only: separate domain and transition stores are not atomically migrated, and the host's fenced commit still checks the expected source.

The application owns the committed `current` state. It remains at the source while work is pending and changes only after target-state work succeeds. On completion, the live entity contains only `current`; transition history retains its source and target. Persist attempt outcomes and terminal transition history alongside the execution's current protocol status; this is not a generic event-sourced log.

After handler work succeeds, persist that success and a stable commit operation ID before calling the host commit boundary. This durable commit-pending marker lets recovery distinguish successful work from an unfinished attempt. The host commit compares the expected `previous` state and current fencing generation. It is idempotent by execution ID and writes a durable commit receipt atomically with the domain-state update. If work success is durable but the receipt is not yet recorded in the execution record, recovery retries or reconciles the same host operation; it does not rerun successful work. If the success marker was not durable, work may repeat and must be idempotent.

When domain state, execution metadata, and notification outbox share a transactional store, one fenced transaction updates `current`, records the commit outcome, and writes enabled notification intent. When stores are separate, the host receipt remains atomic with domain state; the runtime reconciles that receipt and continues the same execution. The durable notification choice in the accepted execution drives an idempotent outbox handoff keyed by execution ID. Do not mark the execution complete until handoff is durable. A failed handoff remains recoverable through `NotificationRepair`; consumer delivery retries independently. No exactly-once effects are promised across stores.

Only one transition execution may be active per entity. A persisted renewable lease issues a monotonically increasing per-entity fencing generation. Lease expiry allows recovery of the same recorded transition; it is not an application deadline or a domain-state change. The host's authoritative commit boundary must reject stale generations, including when transition metadata and domain state use separate stores.

## Protocol phases

```mermaid
stateDiagram-v2
    [*] --> Waiting: transition accepted
    Waiting --> Running: attempt starts
    Running --> Waiting: app policy authorizes retry
    Running --> Notifying: work succeeds, state committed, notification enabled
    Running --> Complete: work succeeds, state committed, notification disabled
    Notifying --> Complete: notification intent durably handed off
    Notifying --> Notifying: outbox handoff retry
    Notifying --> NotificationRepair: handoff requires a decision
    NotificationRepair --> Notifying: authorized handoff retry
    NotificationRepair --> Complete: authorized waiver durably recorded
    Running --> NeedsIntervention: policy exhausted or requires a decision
    Waiting --> NeedsIntervention: deadline policy requires a decision
    NeedsIntervention --> Waiting: authorized retry of same transition
    NeedsIntervention --> Aborting: explicit pre-commit abort
    Waiting --> Aborting: explicit abort before work
    Aborting --> Aborted: recovery outcome durably recorded
    Complete --> [*]
    Aborted --> [*]
```

- **Waiting**: the accepted transition is waiting to run or retry.
- **Running**: the target state's transition handler is executing.
- **Notifying**: the domain state is already committed; notification intent is being durably handed off.
- **Complete**: the transition execution is settled. A later request creates a new execution record.
- **NeedsIntervention**: a pre-commit application policy or exhausted retry budget requires an application/operator decision. The old current state remains committed, and the pending target remains recorded.
- **NotificationRepair**: the target current state is already committed, but notification intent is not durably handed off. Retry the handoff or record an authorized waiver; do not roll back or abort the committed domain transition.
- **Aborted**: the transition was explicitly abandoned; it is not a successful completion. The old current state remains committed, and history records that external side effects may remain.

Errors, timeouts, retry counters, and lease ownership are execution metadata/outcomes, not domain states. The application supplies and versions/pins the policy for retry classification, attempt limits, retry delay, per-attempt execution timeout, and overall transition deadline. Lease expiry is only lock recovery. The framework supplies no hidden retry count, timeout, or retry schedule.

The original error labels map to protocol outcomes as follows:

| Draft label | Protocol meaning |
| --- | --- |
| State change timeout | Overall transition deadline; application policy chooses retry or intervention |
| Too many tries | Application retry budget is exhausted; enter `NeedsIntervention` before commit |
| State change execution error | Attempt result classified by application policy as retryable or requiring intervention |
| State change execution timeout | Per-attempt work timeout, handled by the pinned application policy |
| Abort execution / lock timeout | Lease ownership expired; recover/reclaim the same transition, not a domain timeout |
| Cancel state change | Explicit pre-commit abort; run recovery hook if needed, then record `Aborted` |

## State hooks and notification

The target state's implementation performs the work for a transition into that state. During creation (`previous = null`), the selected initial state's entry hook runs through the same protocol. The common typed Go state contract includes transition, initial-entry, retry, and recovery hooks; a state with no work implements an explicit no-op.

- The retry hook runs only after an attempt fails and the pinned policy authorizes a retry. It may prepare or reconcile partial work but cannot change the selected target or choose retry limits. A retry-hook failure is recorded and handled under the same policy.
- The recovery hook runs only for an explicit pre-commit abort/repair, not for automatic retries or post-commit notification repair. It may compensate or reconcile partial side effects. An empty implementation means no recovery work is needed. Its progress is persisted and uses the same retry/deadline policy.
- Retry and recovery code must be idempotent because work may be repeated after failure.
- Each transition rule has a notification default, which the caller may override for that execution. Persist the chosen setting. When enabled, persist a notification intent/outbox with the commit where possible; complete on durable handoff, not consumer processing. If the handoff cannot be durably recorded after domain commit, enter `NotificationRepair`; an authorized decision may retry or durably waive it. Delivery retries independently after handoff. When notification is disabled, skip it and complete after the domain commit.

## Commit and failure rules

1. Validate the idempotency key and select one allowed target using the application rule.
2. Record the transition snapshot and acquire/renew its per-entity lease.
3. Run the target state's transition handler. The current domain state remains unchanged.
4. On success, commit the target as current and clear pending transition fields. Record source/target in history and persist notification intent when enabled. If handoff cannot be made durable after the domain commit, enter `NotificationRepair` with the new current state.
5. On a retryable failure, apply the pinned application policy, wait as directed, run the retry hook, then retry the same transition. Per-attempt timeout and overall transition deadline are distinct; application policy decides their outcomes.
6. On retry exhaustion or a policy requiring intervention before commit, retain the failure history and pending target. An authorized application/operator may retry the same transition or explicitly abort it.
7. An explicit pre-commit abort runs the recovery hook (which may be a no-op), records any possible remaining side effects, leaves current unchanged, and releases the lease only after the abort is durable.
8. For `NotificationRepair`, retain the lease and new current state. An authorized application/operator may retry the handoff or record a durable waiver; only then release the lease and settle the transition execution.

No cross-store exactly-once guarantee is made. If the application stores domain state separately from transition metadata, its commit operation and any external side effects must be idempotent and recoverable.
