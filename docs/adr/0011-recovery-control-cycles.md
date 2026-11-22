# Renew recovery budgets only at authorized decisions

An elapsed deadline or exhausted recovery budget must not silently cancel an
accepted transition or leave recovery impossible. Each new authorized retry or
abort starts a fresh attempt budget and deadline using the pinned
`OverallTimeout`, while preserving the original deadline and prior history;
identical control replay does not renew either. Recovery exhaustion enters
`NeedsIntervention`, where retry resumes recovery. A definitive host commit
rejection itself authorizes abort and recovery, superseding the separate abort
authorization in ADR 0010; unknown outcomes and stale fences do not.
