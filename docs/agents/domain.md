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
