# Using the FSM and runtime

Use this guide when designing or implementing a host workflow. The
[architecture baseline](../architecture.md) and linked ADRs are authoritative;
the [Go implementation README](https://github.com/reinaldoborges/rff-go/blob/master/README.md)
documents the current implementation and host wiring. The Go framework is
experimental; passing the first-slice gate is not a production-readiness claim.

**Status:** Manual transition requests and the durable transition runtime are
available. Runtime-managed automatic Continuation and Downstream operation
tracking are approved designs, **not implemented**. Do not call them as
existing facilities. See [ADR 0012](../adr/0012-durable-transition-continuation.md)
and [ADR 0013](../adr/0013-track-downstream-operations-within-transitions.md)
when implementing those features.

## Choose the execution model

1. Define application-owned entity IDs, states, events, inputs, and a versioned
   machine. Keep selectors and guards pure; define a target-state handler for
   each state and classify failures using safe data. Initialization selects an
   initial state separately, without a synthetic event.
2. Use the FSM alone for deterministic selection when the host will execute
   work, persist state, and handle recovery itself. The machine selects; it
   does not run hooks or commit state. See the
   [standalone example](https://github.com/reinaldoborges/rff-go/tree/master/examples/fsm).
3. Use the runtime when accepted transitions need durable progress, worker
   retries, and recovery. Supply the persistence adapter, versioned codecs,
   host domain commit and authorization. Schedule workers and all applicable
   reconciliation scans; wakeups are hints, so poll and recover after errors.
   The host still owns domain state, side-effect idempotency, and audit.
4. Choose domain states that represent meaningful, committed milestones or
   waiting points. Put external work for a milestone in its **target** handler:
   it runs before that target becomes current. Split a process when milestones
   require separate retry or recovery behavior; do not make `Retrying` a domain
   state. A later reversal of a committed milestone is an application-defined
   transition, not automatic rollback.

```mermaid
sequenceDiagram
    participant H as Host
    participant R as Runtime
    participant W as Worker
    participant D as Host domain store
    H->>R: Request event with stable key
    R->>R: Select target and reserve entity durably
    R->>W: Run target-state hook
    W-->>R: Success or classified failure
    alt Hook succeeded
        R->>D: Fenced domain commit
        D-->>R: Durable success or rejection receipt
    else Hook failed
        R->>R: Retry or require intervention
    end
    R-->>H: Inspect progress and committed outcome
```

Acceptance means the execution was recorded, **not** that the new state was
committed. Only one transition execution may be active per entity; a different
request while reserved is busy. The host commit checks the expected state and
fence. If stores are separate, reconcile its durable receipt rather than
re-running successful work. See [ADR 0004](../adr/0004-host-supplied-transition-persistence.md).

## Advance the workflow

- **Explicit request or human decision, available now:** After the prior
  execution has completed and released its reservation, submit the next event
  with a stable idempotency key. For a human wait, commit a meaningful waiting
  state, then use typed human-decision ingress when the user responds. The host
  authorizes and maps that input to a transition; the runtime does not provide a
  UI or receiver.
- **Automatic progression, available now only with host orchestration:** The
  host must durably discover the committed milestone, decide and persist the
  next request, and reconcile delivery using the same key. Account for crashes,
  a still-held reservation, changed domain state, and duplicate or unknown
  acceptance. A call from the target hook is too early: the target has not yet
  committed and the entity is reserved. A transient wakeup alone is not durable.
- **Runtime-managed Continuation, planned:** Opt in per committed state;
  host-owned, version-pinned behavior makes the decision after commit. The
  intended contract covers durable discovery, stale-origin checks, replay,
  authorization, separate budgets, and operator controls. Follow
  [ADR 0012](../adr/0012-durable-transition-continuation.md) rather than
  assuming this machinery exists today.

## Set a policy for each transition

The host selector supplies `fsm.Policy`; the runtime pins the selected policy
when it accepts the request. Set `MaxAttempts`, `AttemptTimeout`,
`OverallTimeout`, and `RetryDelays` explicitly; there are no framework
defaults. For example, these are **illustrations, not recommended defaults**:

```go
short := fsm.Policy{
    MaxAttempts: 3, AttemptTimeout: 5 * time.Second,
    OverallTimeout: 30 * time.Second,
    RetryDelays: []time.Duration{time.Second},
}
long := fsm.Policy{
    MaxAttempts: 3, AttemptTimeout: 20 * time.Minute,
    OverallTimeout: 2 * time.Hour,
    RetryDelays: []time.Duration{2 * time.Minute},
}
```

- `MaxAttempts` includes the first attempt and **all started hooks** in a
  control cycle, including `Retry` and `Recover`. For example, a failed
  transition hook, successful retry hook, and redelivered transition hook use
  three attempts. A started attempt with an unknown outcome also counts.
- `AttemptTimeout` limits one attempt; `OverallTimeout` starts at acceptance and
  includes queueing, work, retry hooks, and delays. Choose both for the actual
  workload and leave room for retries. Lease expiry is a separate mechanism.
  A timed-out hook that ignores cancellation may still cause external effects.
- Configure at least one retry delay for automatic retries. The last delay
  repeats after the schedule is exhausted; an empty schedule requires
  intervention. Attempt or deadline exhaustion does not silently abort.

For budget renewal and history, see
[ADR 0011](../adr/0011-recovery-control-cycles.md) and the
[acceptance matrix](../first-slice-acceptance.md#requests-concurrency-and-retries).

## Retry, recover, or abort

```mermaid
flowchart TD
    A[Target hook starts] -->|success| C[Fenced domain commit]
    A -->|retryable failure| R[Retry hook, then original hook]
    R -->|within policy| A
    A -->|exhausted or intervention| I[NeedsIntervention]
    R -->|exhausted or intervention| I
    I -->|authorized retry| S[Resume blocked hook]
    S -->|Enter or Transition| A
    S -->|Retry| R
    I -->|authorized abort| B[Recover hook]
    C -->|definitive rejection| B
    B -->|success| X[Aborted]
    B -->|exhausted| IR[NeedsIntervention during recovery]
    IR -->|authorized retry| B
```

The diagram summarizes outcomes, not every protocol status. An authorized retry
or abort starts a fresh attempt budget and deadline; an identical control replay
does not renew them. A definitive commit rejection automatically starts
recovery; an unknown commit outcome is reconciled, not treated as rejection.
The host defines compensation, and recovery cannot guarantee external effects
are undone. A post-commit notification failure uses notification repair or
waiver, not transition abort. For phase gates and unknown attempts, read the
[architecture baseline](../architecture.md#infrastructure).

## Downstream calls

- **Available now:** Hook delivery is at least once. Make downstream effects
  idempotent using stable identities, and store any needed per-operation
  receipts or checkpoints in host-owned durable storage. A timeout or crash
  may leave the outcome unknown; reconcile with the downstream system before
  repeating an unsafe call. If no safe reconciliation or repeat is possible,
  surface the uncertainty for intervention. Leases fence runtime reports, not
  external systems.
- **Planned optional tracking:** The runtime will track host-selected operations
  within a transition execution, including selected reads and compensation.
  It will preserve operation identity and safe results, handle unknown
  outcomes, and retain host-defined recovery decisions. This is not a
  general-purpose activity lifecycle or an exactly-once guarantee. Read
  [ADR 0013](../adr/0013-track-downstream-operations-within-transitions.md)
  before designing against it.

## One transition for a batch

For a renewal run, the host may use one batch entity and one target-state hook
to process many records:

1. Give the run a stable identity; persist its membership or a restart-safe
   enumeration cursor and durable per-record progress in host storage.
2. For each record, use a stable business operation key and reconcile unknown
   downstream outcomes before repeating an effect. Persist a result or
   checkpoint after confirmed work; a crash between an external effect and the
   checkpoint still requires downstream idempotency or reconciliation.
3. On retry, resume unfinished records; return an error for the host classifier
   when the batch cannot complete under its policy. Commit the target batch
   state only after the hook succeeds and the host commit validates its invariants.
   Decide explicitly how partial failure, cancellation, and compensation work.
4. Protect records against concurrent runs in the host: the runtime reservation
   covers the **batch entity**, not each record. Size the attempt and overall
   timeouts for the workload, or split it into smaller domain milestones.

Alternatively, give each record an entity and independent transition
execution; the host still owns durable fan-out and batch aggregation. Neither
approach supplies a built-in batch lifecycle or exactly-once external effects.
