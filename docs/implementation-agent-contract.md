# First-slice coding-agent implementation contract

This contract guides implementation planning in this home repository and work in the future `reinaldoborges/rff-go` repository. The home repository remains authoritative for the architecture, glossary, ADRs, and [first-slice acceptance matrix](first-slice-acceptance.md).

## Repository guidance and executable contracts

- The implementation repository has a concise root `AGENTS.md` with day-to-day instructions, links to the home design, the supported Go version, and verified build and verification commands. Avoid copying the full design into it.
- Provide a runnable standalone FSM example and a runnable task-manager fixture, with documented commands and automated checks that keep them working. The fixture and reusable adapter conformance harness remain internal; expose the local/test fixture CLI under `cmd/`.
- Use executable Go tests and adapter conformance suites as the initial machine-readable contracts. Add a separate schema or formal contract format when a specific interface needs one, not as a blanket prerequisite.

## Implementation issues and design changes

Every implementation issue in the home repository identifies:

- The target repository, component, and scope.
- Relevant home-repository design and decision references pinned to specific revisions.
- Dependencies and observable acceptance criteria.
- Exact verification commands; explicitly mark commands pending if bootstrap has not yet made them available.

Issue acceptance is scoped to the change, not the entire first-slice matrix. Implementation PRs link to their home issues and relevant decisions; cross-repository links do not automatically close home issues.

If implementation exposes a missing decision or conflicts with the design, stop the affected work and raise it in the home issue instead of silently changing the contract. Record an approved design change in the authoritative home documentation. If the design changes after an issue pins a revision, flag the difference and reconcile it before updating the issue's references and acceptance criteria; link the relevant revision from the implementation work.

## Bootstrap and verification

Initial implementation work establishes the Go module, pins the supported Go toolchain, and adds root agent guidance and executable check commands. Bootstrap issues state the commands they introduce and verify them in their own changes. Pending or placeholder commands are not passed checks.

Work on a feature-specific branch or `develop`, keeping implementation changes off the default branch. The Go workflow runs on pull-request events only, so opening, reopening, or updating a PR starts CI. Run the issue-specific checks and repository baseline locally before opening a PR, and batch follow-up changes before updating an open PR to avoid redundant runs.

Document and verify the actual formatting, vet, test, and race-check commands in the implementation repository. Prefer standard Go tooling unless a specific need justifies more tooling; no exact commands or Go version are prescribed before the repository exists.

Each change must pass its issue-specific checks and applicable repository formatting, vet, and test checks locally before its PR is opened. CI enforces the same baseline and runs the complete Go test suite, including durable-adapter and real-process restart tests, plus race detection on supported platforms. Documentation-only changes run applicable documentation checks rather than unrelated Go checks. Report unavailable, unsupported, or blocked checks explicitly rather than treating them as passed.

Before declaring the first slice usable, the complete [acceptance matrix](first-slice-acceptance.md) must pass, including persistence and restart cases against at least one real durable adapter. The concrete adapter remains an implementation choice; this is a correctness and recovery gate, not a production-readiness claim.
