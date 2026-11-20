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
A deterministic model of states and allowed transitions, independent of workflow execution and persistence.

**Activity**:
An application-defined operation that a workflow invokes to perform work outside its deterministic state machine. An activity may be retried.

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
The relationship between a user and a group, including that user's role in the group.

**Group owner**:
The sole owner of a group, who is also a member and manages the group's membership.

**Group member**:
A user with membership in a group and permission to manage that group's tasks.

**Task**:
A unit of work belonging to one group, optionally assigned to one of that group's members.

**Invitation**:
A time-bounded request from a group owner for a known user to join the group.
