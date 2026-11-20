# Use host-supplied persistence for transition execution

The framework defines the transition-execution record and typed persistence port, while the host application configures and injects the adapter; committed domain state and entity schema remain application-owned. This permits transition metadata to share the application's store when useful, but separate stores require idempotent commits and reconciliation rather than an exactly-once cross-store guarantee.
