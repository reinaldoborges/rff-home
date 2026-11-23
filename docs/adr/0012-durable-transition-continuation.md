# Make automatic continuation durable after commit

The optional runtime will coordinate durable Continuations for states explicitly
opted in by the host, including initial states. After a successful domain
commit, the host decides whether to request a subsequent transition. This
decision is side-effect-free, may inspect durable domain data, and can be
evaluated again until recorded; the first recorded next event or decision not to
continue is retained for replay. Continuation behavior is pinned to the
originating machine version. Missing behavior blocks visibly; migration of
pending Continuations is deferred.

Persist Continuation intent atomically with the domain commit when stores share
a transaction. Otherwise, the host must provide durable, replayable discovery
of committed transitions requiring Continuation so the runtime can reconcile a
missing intent from the commit receipt. A transient notification is not
sufficient. This supports both persistence arrangements without claiming
exactly-once cross-store effects.

Deliver a recorded successor request at least once with a stable identity.
Reconcile an unknown acceptance outcome by that identity before checking
whether the originating commit is stale. An unaccepted request is superseded
if another transition has advanced the entity, even if the state value later
returns to the same value; the host must enforce the originating commit
identity or revision when accepting the successor. The host supplies a
workload identity and authorizes it at successor acceptance. If the preceding
execution still holds its reservation, wait for release without consuming
Continuation attempts or its evaluation deadline.

Continuation has a separately configured retry budget and deadline; exhaustion
or a definitive non-stale rejection requires intervention rather than silent
loss. Authorized operators may retry with a fresh budget and deadline, or
waive the Continuation with an audit record. Preserve earlier history and do not
renew the budget on an identical control replay. Retry reuses a recorded
decision. A successfully accepted successor has its own transition execution
and recovery; failure does not automatically undo the preceding commit. There
is no framework-wide automatic-chain length limit.

Human decisions continue through existing typed ingress after the application
commits a meaningful waiting state, rather than holding a transition execution
open. This decision describes intended behavior, not an implemented
Continuation facility.

For the detailed implementation contract, see
[Continuation and downstream-operation implementation contract](../fsm-runtime-implementation-contract.md).
