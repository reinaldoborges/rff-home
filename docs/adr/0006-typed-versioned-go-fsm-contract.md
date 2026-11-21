# Define a typed, versioned Go FSM contract

The first Go API uses application-owned generic entity/state/event/input types, pure versioned selectors, immutable hook contexts, and a host-owned fenced commit rather than a framework transition DSL or mutable framework-owned entities. Persisting the selected target, serializable policy, notification choice, and safe failure envelope keeps accepted work recoverable without re-running application decisions; the API remains experimental pending real-adopter validation.
