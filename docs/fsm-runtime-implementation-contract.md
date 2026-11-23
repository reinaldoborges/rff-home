# Continuation and downstream-operation implementation contract

This contract specifies the planned runtime facilities in
[ADR 0012](adr/0012-durable-transition-continuation.md) and
[ADR 0013](adr/0013-track-downstream-operations-within-transitions.md). Neither
facility is implemented yet. For host usage scenarios, read the
[FSM/runtime guide](agents/fsm-runtime.md). The linked decision comments record
the tradeoffs; this document is the revision-pinned implementation contract.

## Boundaries

- The host owns the machine, domain state, persistence adapter, authorization,
  failure classification, operation adapters, compensation, and business
  deduplication. Hooks run before their target state commits. Continuation is
  optional per committed state, including initialization; operation tracking is
  optional per call. Neither facility is a general-purpose scheduler.
- Hooks and downstream effects are at-least-once. Runtime fencing rejects stale
  reports; it does not stop an external call. No exactly-once external effect
  or automatic undo of a previously committed state is promised.
- Durable polling is required even if wakeups exist. The host schedules
  reconciliation, observes errors, and authorizes inspection and controls.
  Persist safe diagnostics, never secrets or raw errors.

## Continuation

### Intent and evaluation

- At transition acceptance, pin eligibility, machine behavior, and an explicit
  Continuation policy for the target state. A successful opted-in commit creates
  one logical intent identified by originating execution and commit operation.
  A definitive rejection or a non-opted-in commit creates none.
- With a shared transaction, atomically persist domain change, receipt, and
  intent. With separate stores, the host atomically retains a discoverable marker
  with the successful commit and receipt. Reconcile replayable markers into the
  runtime; acknowledge or advance a cursor only after persistence. Failed
  pagination gaps remain durably retryable. Duplicate and conflicting markers
  are respectively replayed or reported explicitly.
- Reconcile a lost host-commit response and wait for the originating reservation
  to be released, including notification repair or handoff. No Continuation
  attempt or deadline is consumed while waiting. Notification being disabled
  does not disable Continuation.
- Use a fenced evaluator with the pinned machine behavior. It is side-effect-free
  and may read current durable data. Before a decision is recorded, a crash may
  cause reevaluation against changed data. Afterwards replay the first durably
  recorded next event or no-continuation decision. Missing behavior blocks
  visibly; do not substitute another version.

Decision: [durable discovery](https://github.com/reinaldoborges/rff-home/issues/33#issuecomment-7106968085).

### Successor acceptance

- Bind one stable successor request identity to the originating intent and
  commit, entity, event, and semantic inputs. Matching replay returns the same
  accepted execution; changed semantics conflict. Reconcile acceptance by this
  identity before checking stale origin. A matching acceptance receipt wins
  even after the entity changes.
- The host supplies a non-reused origin identity or revision that changes on
  every committed FSM-state change, including changes by writers outside the
  runtime. Compare it atomically at acceptance and establish a durable fence
  respected by all such writers. State-value equality alone cannot detect
  A-to-B-to-A. A proven unaccepted request with a changed origin is superseded;
  pending, conflicting, or unverifiable evidence remains visible.
- For separate stores, the runtime prepares under its entity reservation; the
  host atomically validates origin and records the authorized acceptance receipt
  and fence; the runtime finalizes the same successor. The host receipt is
  authoritative if finalization or the response is lost. Persist sufficient
  evidence to recover that execution. A shared store can do this atomically.
- Provisional claims are not accepted executions. Never treat a lost response
  as proof of absence. Release a host fence only after safe release by the
  accepted execution or fenced cancellation proving the prepared request can
  no longer be accepted. Stuck claims require observable repair. A host unable
  to enforce the fence must explicitly block or reject acceptance.
- Authenticate and authorize the host workload principal for every new
  acceptance. Record its principal and authorization decision with the receipt;
  later credential rotation or policy changes do not undo acceptance. A
  definitive denial requires intervention; a temporary authorization failure
  can retry. Host authorization separately controls replay and inspection
  disclosure and must not prevent internal recovery.

Decision: [acceptance and origin races](https://github.com/reinaldoborges/rff-home/issues/35#issuecomment-7108260407).

### Policy and controls

- The host supplies a maximum attempt count, per-attempt timeout, overall
  active-time deadline, and retry delays; there are no implicit defaults. One
  started drive may evaluate and deliver; it counts even if its outcome is
  unknown. A claim lost before start does not count. A subsequent drive reuses a
  recorded decision. Use successive delays, repeating the last; an empty
  schedule requires intervention.
- Start the first cycle when the successful origin receipt and original
  reservation release are durably observed. Queueing, retry delays, downtime,
  and compatibility blocks consume its deadline. A recorded reservation wait
  parks the same drive and pauses its remaining per-attempt and overall time
  across restart, without charging another attempt. Do not park over an
  unresolved in-flight acceptance or refund an already elapsed timeout.
- Exhaustion, deadline expiry, or definitive non-stale rejection requires
  intervention. Acceptance lookup and finalization of already accepted work
  remain allowed after exhaustion; they do not authorize a new delivery.
  Restored pinned behavior resumes within the existing budget, not a fresh one.
- An authorized retry from intervention starts a fresh cycle with the pinned
  policy and preserves history. Reuse an existing decision and identity; if no
  decision was recorded, reevaluate. Reconcile an unknown acceptance before
  another delivery.
- An authorized waiver may be requested before acceptance, including while
  waiting or compatibility-blocked. Finalize it only after pending evaluation
  and acceptance are reconciled or fenced so they cannot later record or
  accept. Unknown acceptance remains pending or rejects the waiver. An accepted
  successor uses its own recovery; waiver never undoes the origin commit or
  bypasses notification repair. Terminal no-continuation, superseded, or
  accepted outcomes cannot be rewritten as waived.
- Retry and waiver are fenced, serialized, authorized, audited with principal
  and safe reason, and deduplicated by stable control-request identity.
  Identical replay returns the prior result without renewing the budget;
  changed semantics conflict. Inspection exposes safe policy, phase, pause,
  history, decision, successor, diagnostics, and control outcomes.

Decision: [policy and intervention](https://github.com/reinaldoborges/rff-home/issues/37#issuecomment-7108937709).

## Tracked downstream operations

### Identity, dispatch, and replay

- The host explicitly invokes a runtime capability bound to the active hook
  attempt. Requesting tracking without that capability fails explicitly. Hooks
  await calls within their existing budget; tracking does not silently fall
  back to untracked calls.
- Identity is `(transition execution ID, host stable operation key)`, shared
  across Enter, Transition, Retry, and Recover. The first use binds operation
  kind, behavior version, and semantic input through a versioned comparator or
  durable immutable reference. Changed semantics conflict; unverifiable
  equality or missing pinned behavior blocks. Batch keys use stable record
  identity and purpose; compensation uses a distinct key.
- The host deterministically maps that identity to a provider-compatible
  idempotency identity without collisions and reuses it across attempts.
  Cross-execution business deduplication remains host/provider-owned.
- Preflight behavior, input, and codecs. Durably record intent and mark dispatch
  as possibly started before invoking the adapter. Persist confirmed success
  and its safe, typed, versioned result or immutable reference before reporting
  success. Explicit no-result success is distinct from missing data. Matching
  replay returns the same result without invoking the provider again.
- Serialize valid claims per identity with durable generations. Stale scopes
  and reports fail explicitly; matching callers may wait or receive pending.
  Different keys may run concurrently under host limits. Transition work cannot
  succeed while started tracked calls are in flight or unresolved; the host
  may intentionally handle a known failure.

Decision: [identity and replay](https://github.com/reinaldoborges/rff-home/issues/34#issuecomment-7107313781).

### Unknown outcomes and intervention

- The host adapter classifies confirmed success, definitive failure, or unknown
  and supplies provider-specific lookup, evidence validation, and safe-repeat
  assessment. Timeout, cancellation, lost response, ambiguous error, or
  process loss is unknown without contrary evidence. A known failure is not
  automatically safe to repeat: automatic retry requires host classification
  as retryable and proof that repeating is safe, including partial effects and
  earlier calls.
- A lookup proves absence only if authoritative for the exact operation and
  earlier dispatches cannot still take effect. A not-found response, expired
  lease, or cancelled context alone is insufficient. Stale responses can be
  considered only as evidence validated through current reconciliation.
- Repeat an unknown mutation only when the exact provider identity, scope, and
  semantic request are covered by a verified idempotency guarantee throughout
  the period in which old and repeated dispatches could both take effect.
  Recheck evidence and validity at use. A tracked read must also preserve its
  original result semantics. Known success with an unavailable required result
  blocks; do not fabricate or blindly repeat it.
- Reconciliation uses the existing hook attempt and transition policy.
  Temporary lookup failures can retry within that policy. An irreconcilable
  unknown requires intervention and blocks dependent progression.
- During intervention, an authorized operator may submit an evidence-backed
  resolution for the exact unresolved operation. Atomically fence stale
  claims, append the validated outcome and safe audit, and deduplicate by
  stable resolution-request identity. Absence evidence must address late calls;
  success must provide the required result. Resolution does not resume work:
  a separate authorized retry or abort follows existing phase gates.
  Conflicting later evidence requires visible intervention, not history rewrite.

Decision: [unknown-outcome reconciliation](https://github.com/reinaldoborges/rff-home/issues/36#issuecomment-7108450162).

### Recovery and compensation

- Recover is host-defined and uses the existing recovery budget. Ordinary
  retry does not automatically compensate. Tracked compensation has a distinct
  stable key and follows the same tracking and reconciliation rules.
- The host declares and durably binds tracked compensation prerequisites.
  Before dispatch and replay, block on unresolved, missing, unverifiable,
  conflicting, or cyclic prerequisites; incomplete declarations fail closed
  against unresolved effects. A claim that an operation never started needs
  reliable evidence under the fencing rules. The host interprets settled
  outcomes and owns equivalent safety for untracked compensation.
- Authorized abort may enter recovery while an operation is unknown; declared
  independent compensation can proceed, while dependent compensation waits.
  Do not record Aborted while any started tracked operation remains in flight
  or unresolved. Host recovery may intentionally handle a known partial effect;
  Aborted means recovery completed, not that every effect was reversed.
- A separate authorized retry or abort starts the existing fresh control cycle
  and pinned deadline, preserving history; identical replay does not renew it.
  Recovery exhaustion returns to intervention. Definitive commit rejection
  retains its existing automatic-recovery rule.

Decision: [recovery and compensation](https://github.com/reinaldoborges/rff-home/issues/38#issuecomment-7109072659).

## Persistence, compatibility, and migration

- Fresh SQLite and MySQL stores provide independently queryable durable
  Continuation and operation records, indexed identities, transactional
  uniqueness and fenced updates, safe evidence, and history. Both adapters
  enforce identical non-lossy identity semantics regardless of collation or
  index limits; digest indexes must verify the full identity. Atomically gate
  transition terminal outcomes against concurrent tracked-operation starts.
- Structural schema versions are distinct from machine/operation behavior,
  semantic comparison, result codec, and evidence versions. Unsupported
  structural schemas fail initialization without writes. Isolate an individual
  unreadable or incompatible new record only when identity and scan position
  remain safe; otherwise fail the affected scan rather than skip it. Preserve
  existing transition-record compatibility guarantees.
- Retain identities, decisions, results, evidence, and control history with
  transition history without automatic expiry. Host-owned immutable references
  remain verifiable and accessible for replay. No migration or backfill of
  existing SQLite/MySQL data is required; reject incompatible existing stores
  without deleting or rewriting their data.
- Preserve the existing authorized, audited per-execution behavior migration
  before durable work success. Atomically fence runtime claims and persist the
  migrated snapshot, preserved operation bindings, and migration receipt. The
  host separately coordinates domain-store cutover.
- Migration preserves eligibility, policy meaning, identities, operation
  behavior/input/provider/result bindings, evidence, prerequisites, attempts,
  deadlines, and control history. The destination must prove compatibility or
  migration blocks. Unknown or in-flight operations may survive only if their
  original bindings and evidence remain usable for reconciliation and stale
  reports are fenced; migration does not stop an external call.
- A transition accepted on machine v1 and migrated to v2 before commit keeps
  the v1 Continuation behavior and policy pinned at acceptance. Validate that
  the destination state can honor them. Migration of pending post-commit
  Continuations remains deferred.

Decision: [versioning and persistence](https://github.com/reinaldoborges/rff-home/issues/39#issuecomment-7109201006).

## Host scenario and conformance

The runnable host models one recurring plan per entity. It commits
`AwaitingApproval`, accepts typed manual approval to commit `Due`, then uses
Continuations for `Due → PaymentCaptured → Renewed`. The `PaymentCaptured`
target hook charges a durable fake provider before commit. The host owns
plan-period deduplication, revision fencing, policies, authorization, and
recovery. Exercise lost responses, late calls and intervention, plus a
pre-commit failure followed by a separately keyed tracked refund. The original
committed state is not automatically undone.

Run shared conformance and real-process restart tests on fresh SQLite and real
MySQL, including shared and separate stores, origin races, unknown effects,
control and authorization races, compatibility, and migration. Exercise both
host-owned batch progress within one transition and host fan-out to one entity
per record. No framework batch scheduler is implied. Report unavailable MySQL
checks as unverified, not passed.

Decision: [host integration scenario](https://github.com/reinaldoborges/rff-home/issues/40#issuecomment-7109366744).
