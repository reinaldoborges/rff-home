# Domain Docs

How engineering skills should consume this repo's domain documentation.

## Before exploring, read these

- `GLOSSARY.md` at the repo root, or `GLOSSARY-MAP.md` if it exists.
- `docs/adr/` for ADRs touching the area being explored.

If these files do not exist, proceed silently. The domain-modeling skill creates them lazily when terms or decisions are resolved.

## File structure

This is a single-context repo:

```text
/
├── GLOSSARY.md
├── docs/adr/
└── src/
```

## Use the glossary's vocabulary

When naming a domain concept in an issue, refactor proposal, or test, use the term defined in `GLOSSARY.md`. If a needed concept is absent, note the gap for domain modeling.

## Flag ADR conflicts

If output contradicts an existing ADR, surface it explicitly rather than silently overriding.

## Implementation revisions

The Go implementation lives in `reinaldoborges/rff-go`, not this repository.
Before tracing it, resolve the revision requested by the task and compare it
with the checkout's `git rev-parse HEAD` and `git status --short --branch`.
For the default branch, `gh api repos/reinaldoborges/rff-go/commits/master --jq .sha`
resolves the remote revision; use the requested branch or commit instead when
one is specified.

Record the dirty state, including relevant uncommitted changes. Pass it, the
resolved commit, and checkout path to delegated explorers, and require them to
confirm the checkout before reporting. If it does not match, use a matching
isolated worktree or report the mismatch; do not silently review a different
revision or alter an existing checkout.
