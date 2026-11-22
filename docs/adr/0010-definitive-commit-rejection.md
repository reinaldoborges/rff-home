# Reconcile definitive host commit rejection before recovery

ADR 0011 supersedes the separate authorized-abort requirement originally
recorded here: definitive rejection itself authorizes automatic recovery. The
remaining receipt and fencing decisions still apply.

Successful transition work does not guarantee that its domain commit remains valid: another domain operation can invalidate the expected source or an invariant before the host commit. Repeating such a commit indefinitely could apply a stale decision later, while treating an unknown response as rejection could contradict a commit that actually succeeded.

The host records a fenced, durable success or definitive rejection receipt for the stable commit operation ID. A rejection changes no domain state and creates no notification intent; reconciliation returns the recorded outcome before re-evaluating the operation. Transient errors, unknown outcomes, and stale fences are not definitive rejections. An execution with a rejection receipt enters `CommitRejected` and retains its reservation through recovery; neither the successful hook nor the rejected commit is retried. A new request is needed if conditions later permit the change.

This adds a protocol phase and can require operator intervention, but prevents stale commits and preserves crash-safe reconciliation across separate stores. Recovery may reconcile or compensate work, but cannot guarantee that external side effects are undone.
