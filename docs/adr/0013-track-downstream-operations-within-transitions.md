# Track downstream operations within transition executions

The optional runtime will support host-selected, durable tracking of Downstream
operations within their authoritative transition execution. This includes
selected reads whose results must remain stable, mutations, and compensation;
untracked calls remain host-managed. The host defines the operations,
downstream adapters, failure classification, and business recovery decisions.
Tracking does not create an independent general-purpose activity lifecycle.

Before dispatch, durably record a host-supplied operation identity and its
semantic input or an immutable reference. The identity is stable within the
transition execution; reuse with different semantic input is a conflict.
Persist a confirmed successful result as host-approved, versioned data or a
durable reference, and reuse it on hook replay instead of repeating the
operation. Persist no secrets or raw errors. Cross-execution business
deduplication remains the host's and downstream provider's responsibility.

Serialize valid claims for an operation and fence stale reports, but do not
assume fencing stops a timed-out downstream call. Attempts for the same
operation use the same downstream idempotency identity. An unknown outcome may
resume automatically only after definitive reconciliation or a safe repeat
under a still-valid downstream idempotency guarantee. A lookup showing absence
is definitive only if it is authoritative and an earlier in-flight call cannot
still take effect. Otherwise require intervention and pause dependent
progression; do not silently assume success or absence.

The host classifies definitively unsuccessful attempts as retryable or final;
only safe-to-repeat attempts can be retried under the existing transition hook
policy and deadline. An authorized host operator may record an audited,
evidence-backed resolution of an irreconcilable unknown. Resolution and
resumption are separate: an authorized retry or abort resumes the existing
recovery cycle, retaining its history. Host-directed recovery reconciles
uncertainty before dependent compensation; ordinary retries do not
automatically compensate. Compensation can use separately identified tracked
operations. Reversal of an earlier committed state remains an explicit host
domain transition.

Pin the relevant operation behavior and result encoding versions, block visibly
when they are unavailable, and re-check downstream idempotency guarantees
rather than assuming they remain valid. Authorized pre-work-success execution
migration must preserve operation identities, outcomes, and their meaning, or
be blocked. Retain operation identities and replay evidence with transition
history; host-owned references must remain available for replay. This decision
describes intended behavior, not an implemented tracking facility, and does
not promise exactly-once external effects.

For the detailed implementation contract, see
[Continuation and downstream-operation implementation contract](../fsm-runtime-implementation-contract.md).
