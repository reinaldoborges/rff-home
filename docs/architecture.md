# RF-DSF Architecture Baseline

This document records the agreed design baseline for RF-DSF. It guides future implementation repositories; it is not a package layout or a complete API specification.

## Product shape

RF-DSF is a domain-neutral framework for application and platform engineers building stateful, long-running systems. Coding agents are first-class users of its documentation and examples. The framework is language-neutral in concept, with Go as the first implementation language, and may be paired with a portable, self-hosted runtime.

Reliability, security, auditability, operability, resilience, and disaster recovery are design goals, not blanket guarantees. Distribution and licensing remain undecided.

## Logical areas

These are conceptual boundaries, not decisions about repositories or Go packages.

### Framework

- Provide optional, composable domain-modeling patterns for types, invariants, validation, and transitions without requiring a particular DDD layering, ORM, or base class.
- Provide optional persistence ports and patterns for applications. Applications own their domain data and persistence choices; there is no mandatory ORM or universal data model.
- Define deterministic domain state machines using typed states, events, guards, and transitions. Applications define their state machines and domain validators; execution statuses such as running, retrying, and notifying are not domain states. Nested business statecharts are deferred.
- Group security capabilities under Security while keeping Cryptography, Key Management, Authentication, and Authorization distinct. Authentication may consume crypto and key-management ports; applications own end-user accounts, identity sources, and domain authorization policy. Workload identity is separate.
- Define capability boundaries and safe cryptographic integration principles now. Concrete crypto APIs, key-management adapters, production identity providers, MFA, and SPIFFE integrations await validated use cases.

### Infrastructure

- The optional workflow runtime manages durable orchestration records, schedules durable timers, and invokes application-defined activities. It does not own application domain data or require domain state to be event-sourced.
- A state change is one generic transition execution per entity, separate from the domain FSM. The framework defines its record and typed persistence port; the host application configures and injects an adapter. The framework does not own the entity schema or store. The first implementation may provide a SQLite adapter.
- The application owns the committed `current` domain state. The transition record snapshots the source (`previous`) and selected target (`next`); current remains unchanged until target-state work succeeds. On completion, live entity state contains only `current`, while history retains the transition endpoints. Where stores can share a transaction, commit the domain state and protocol outcome atomically; otherwise use idempotent application commits and recoverable reconciliation, without an exactly-once cross-store promise.
- Each entity has at most one active transition execution. A different concurrent request receives an explicit busy/conflict result; a duplicate idempotency key returns the existing result. A renewable persisted lease with a fencing token permits recovery after worker loss.
- The application evaluates selection and event/guard rules once on acceptance. Persist the chosen target, relevant machine/transition version, pinned execution policy, idempotency key, and the minimal input or immutable reference needed for retry and audit. Retries continue the same logical transition.
- The target state's transition handler runs before the new current state is committed. Entity creation is an initial transition (`previous = null`) selected by the application and runs the chosen state's entry hook. The state contract also includes retry and recovery hooks; unused hooks may be explicit no-ops.
- State-change deadlines and per-attempt execution timeouts are distinct from lease expiry. Exhausted pre-commit attempts enter a needs-intervention outcome; an authorized retry continues the same transition, while an explicit pre-commit abort may invoke the application recovery hook. `Aborted` is distinct from `Complete`, preserves the old current state, and records that external side effects may remain.
- Successful work commits the new domain state before notification. Notification is configurable by transition and may be overridden for an execution; persist that choice. When enabled, create a durable notification intent/outbox and consider the protocol complete on durable handoff, not consumer processing. Delivery retries independently. If disabled, complete after the domain commit.
- If notification handoff fails after the domain state has committed, retain the new current state and require notification repair or an authorized, durably recorded waiver; do not roll back or abort the committed domain transition. Block a different transition until handoff is durable or waived.
- Commands start workflows. External events, timers, and explicit human decisions may advance them; activities perform side effects outside deterministic state-machine logic.
- Workers claim leased activities, renew leases while active, and shut down gracefully. Delivery is at least once; handlers and side effects must be idempotent.
- Applications supply typed retry and timeout policies for activities and transitions. The runtime validates, persists, and enforces the effective policy; in-flight work keeps its pinned policy unless explicitly updated. Retry count, per-attempt timeout, transition/workflow deadline, and overall execution deadline are distinct. Workflow cancellation is explicit and compensation is application-defined.
- Persist workflow transition, attempt, and worker history needed for recovery and diagnosis. Applications own business audit records. Do not persist secrets in workflow payloads or logs; retention periods remain deployment-specific.
- Persist and deduplicate workflow starts and external inputs. Reuse of an idempotency key with a different payload is an explicit conflict. Propagate stable activity idempotency keys, but do not promise exactly-once effects across stores or services.
- The first runtime is a documented single-node baseline. The framework may provide SQLite as its first transition-record adapter, which the host application injects. An in-memory queue is a transient wakeup path; polling and reconciliation recover work after notification loss or process restart. Multi-node coordination is a future capability whose design is deferred.
- A single logical coordinator schedules work, manages leases/retries, and observes worker health. Do not assume process-local ownership is a permanent contract.
- Include structured logs, health/readiness checks, and basic workflow/worker metrics. Defer distributed tracing and advanced dashboards until justified by deployment needs.
- Keep the runtime embeddable and typed-Go-first. A small development CLI may start or signal fixture workflows and inspect status. HTTP, event receiver, and scheduled-start integrations are adapters, not FSM or worker definitions. MCP integration is deferred pending a concrete use case.
- SQLite is the first candidate adapter for transition records. In-memory pub/sub is only a wakeup mechanism. MySQL, PostgreSQL, object storage, caches, secrets stores, cloud connectors, and dedicated brokers are candidates, not commitments.

### Test Suite

The task manager is a small conformance domain, not the product's first industry vertical:

- Users may belong to multiple groups. Membership and permissions are group-scoped; access in one group grants no access to another.
- A group has exactly one owner, who is also a member, and zero or more members. Ownership transfer is explicit. The owner cannot leave or be removed before transfer or group closure.
- Tasks belong to one group, may be unassigned, and may only be assigned to current group members. Any current member may create, update, assign, complete, or cancel tasks. Tasks move from open to in progress to done, or may be cancelled before completion; invalid transitions are rejected.
- Before removing a member, tasks assigned to that member must be unassigned or reassigned.
- An owner may invite a known user. At most one active invitation may exist per group/user; repeat issue requests while pending are idempotent. The invitee accepts or declines before expiry; the owner may revoke. Expiry, decline, revocation, and acceptance are terminal outcomes. Only acceptance creates membership.
- Closing a group revokes pending invitations and cancels their workflows, blocks further membership and task changes, and retains existing records as read-only history.
- The fixture uses seeded opaque user identities, not a login or account system. It exercises authorization denials as well as allowed actions. Crypto is tested separately rather than added artificially to the task domain.

## First implementation slice

The first Go implementation should prove a single-node runtime end to end: typed deterministic state machines, an application-injected transition persistence adapter (with SQLite available as the first adapter), transient in-memory wakeups with recovery polling, leased worker/activity contracts, and the task-manager fixture with invitation workflows. Tests should cover duplicate delivery, retries, expiry, process restart/recovery, and authorization denials.

The first slice excludes multi-node coordination, cloud-specific adapters, production identity-provider integrations, concrete crypto/KMS APIs, MCP, and a production control plane. Framework APIs remain experimental until validated adopters establish a stable release.

## Home repo responsibilities and deferred decisions

This home repo is the source of definitions, architecture decisions, and GitHub planning issues. Each implementation issue should identify its target implementation repository/component, acceptance criteria, and relevant verification commands. The number and structure of implementation repositories and Go packages remain undecided.

Also deferred: the permanent project name; distribution and licensing; a real first-adopter workflow (choose one before freezing APIs); multi-node coordination design; additional storage, messaging, and identity adapters; concrete crypto/authentication mechanisms; numeric RTO/RPO and availability targets; and stable API compatibility guarantees.
