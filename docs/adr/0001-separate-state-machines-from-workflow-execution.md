# Separate state machines from workflow execution

Keep application-defined state machines deterministic and independent of persistence; the optional runtime owns durable workflow progress, timers, and activity invocation. This preserves application ownership of domain state while allowing orchestration to survive worker and process failures.
