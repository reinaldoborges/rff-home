# RF-DSF

RF-DSF is the working name for a framework and optional runtime for building software that coordinates complex, stateful operations.

## Framework and execution

**Framework**:
Reusable capabilities and patterns that application teams may adopt to model and build their domain software.

**Runtime**:
The optional infrastructure that persists workflow progress and coordinates workers.

**Workflow**:
A long-running operation that progresses in response to commands, events, timers, and activity outcomes.

**State machine**:
A deterministic model of application-visible states and permitted event/guard-driven transitions. It excludes execution statuses such as retrying or notifying.

**Transition execution**:
The persisted processing of one accepted request to move an entity from its committed state to a selected target state, including work attempts and notification handoff.

**Integrity finding**:
A durable report that persisted runtime data is unreadable or inconsistent and needs investigation or correction. Unavailable pinned behavior alone is a compatibility issue, not an integrity finding.

**Continuation**:
The application-directed advance of a workflow from a committed state without waiting for an external decision.

**Activity**:
An application-defined operation that a workflow invokes to perform work outside its deterministic state machine. An activity may be retried.

**Downstream operation**:
A host-defined interaction with another system that reads data or causes an effect.

**Worker**:
A runtime component that claims and executes activities.

**End-user identity**:
An identity belonging to an application; the application owns its account lifecycle and domain permissions.

**Workload identity**:
An identity representing a worker or other software component acting within the runtime.

## Security

**Authentication**:
The optional capability to establish or validate a principal's identity using credentials or other proof.

**Authorization**:
A decision about whether a principal may perform an action; application domain permissions remain application-owned.

**Cryptography**:
Methods used to protect information or verify its integrity and origin.

**Key management**:
The custody and lifecycle of cryptographic keys, separate from the cryptographic operations that use them.

## Test domain

**Group**:
A task-sharing boundary with its own membership, owner, and tasks.

**Membership**:
The relationship between a user and a group, including its lifecycle and role. An invited membership grants no group access until accepted. The group owner may end an Active Membership; the removed member loses group access while the Membership remains part of the group's history.

**Group owner**:
The sole owner of a group, who is also a member and manages the group's membership.

**Ownership transfer**:
The change of a group's owner from one active member to another.

**Group member**:
A user with an active membership in a group and permission to manage that group's tasks.

**Task**:
A unit of work belonging to one group, optionally assigned to one of that group's members.

**Invitation**:
The invited phase of a membership lifecycle, in which a known user has been invited to join a group but has no group access.
