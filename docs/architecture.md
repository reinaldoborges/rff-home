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
- Define flat, deterministic state machines using typed states, events, guards, and transitions. Applications define their state machines and domain validators. Nested statecharts are deferred.
- Group security capabilities under Security while keeping Cryptography, Key Management, Authentication, and Authorization distinct. Authentication may consume crypto and key-management ports; applications own end-user accounts, identity sources, and domain authorization policy. Workload identity is separate.
- Define capability boundaries and safe cryptographic integration principles now. Concrete crypto APIs, key-management adapters, production identity providers, MFA, and SPIFFE integrations await validated use cases.

### Infrastructure

- The optional workflow runtime owns durable orchestration records, schedules durable timers, and invokes application-defined activities. It does not own application domain data or require domain state to be event-sourced.
- Commands start workflows. External events, timers, and explicit human decisions may advance them; activities perform side effects outside deterministic state-machine logic.
- Workers claim leased activities, renew leases while active, and shut down gracefully. Delivery is at least once; handlers and side effects must be idempotent.
- Applications supply typed retry and timeout policies. The runtime validates, persists, and enforces the effective policy. Retry count, per-attempt timeout, transition/workflow deadline, and overall execution deadline are distinct. A policy change applies to new work unless an explicit application transition updates an in-flight execution.
- Exhausted retries enter an explicit failed/needs-intervention state. An authorized operator or application decision may retry, resolve, or terminate the execution. Cancellation is an explicit transition; compensation is application-defined, never assumed.
- Persist workflow transition, attempt, and worker history needed for recovery and diagnosis. Applications own business audit records. Do not persist secrets in workflow payloads or logs; retention periods remain deployment-specific.
- Persist and deduplicate workflow starts and external inputs. Reuse of an idempotency key with a different payload is an explicit conflict. Propagate stable activity idempotency keys, but do not promise exactly-once effects across stores or services.
- The first runtime is a documented single-node baseline. SQLite is authoritative for runtime execution records. An in-memory queue is a transient wakeup path; polling and reconciliation recover work after notification loss or process restart. Multi-node coordination is a future capability whose design is deferred.
- A single logical coordinator schedules work, manages leases/retries, and observes worker health. Do not assume process-local ownership is a permanent contract.
- Include structured logs, health/readiness checks, and basic workflow/worker metrics. Defer distributed tracing and advanced dashboards until justified by deployment needs.
- Keep the runtime embeddable and typed-Go-first. A small development CLI may start or signal fixture workflows and inspect status. HTTP, event receiver, and scheduled-start integrations are adapters, not FSM or worker definitions. MCP integration is deferred pending a concrete use case.
- SQLite is the first runtime persistence adapter. In-memory pub/sub is only a wakeup mechanism. MySQL, PostgreSQL, object storage, caches, secrets stores, cloud connectors, and dedicated brokers are candidates, not commitments.

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

The first Go implementation should prove a single-node runtime end to end: typed deterministic state machines, SQLite-backed workflow progress, transient in-memory wakeups with recovery polling, leased worker/activity contracts, and the task-manager fixture with invitation workflows. Tests should cover duplicate delivery, retries, expiry, process restart/recovery, and authorization denials.

The first slice excludes multi-node coordination, cloud-specific adapters, production identity-provider integrations, concrete crypto/KMS APIs, MCP, and a production control plane. Framework APIs remain experimental until validated adopters establish a stable release.

## Home repo responsibilities and deferred decisions

This home repo is the source of definitions, architecture decisions, and GitHub planning issues. Each implementation issue should identify its target implementation repository/component, acceptance criteria, and relevant verification commands. The number and structure of implementation repositories and Go packages remain undecided.

Also deferred: the permanent project name; distribution and licensing; a real first-adopter workflow (choose one before freezing APIs); multi-node coordination design; additional storage, messaging, and identity adapters; concrete crypto/authentication mechanisms; numeric RTO/RPO and availability targets; and stable API compatibility guarantees.
