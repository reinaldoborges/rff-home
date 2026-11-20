# Separate state machines from workflow execution

Keep application-defined state machines deterministic and independent of persistence; execution statuses such as running, retrying, and notifying are not domain states. A separate generic per-entity transition protocol records the selected source/target and execution progress, and commits the new current state only after target-state work succeeds. This preserves application ownership of domain state while allowing transitions and workflows to recover from worker and process failures.
