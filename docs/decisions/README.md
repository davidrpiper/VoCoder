# Architecture Decision Records

Decisions made **after** DESIGN.md v1, or that change it. DESIGN.md stays the current picture;
ADRs record *why* it changed, so later sessions don't re-litigate settled questions.

- File name: `NNNN-short-slug.md` (next number = highest + 1).
- Write one when a decision affects module boundaries, protocols, dependencies, the bridge, the
  process model, or overturns something in DESIGN.md. Spike outcomes (Phase 0) each get one.
- Once **Accepted**, don't edit the decision — supersede it with a new ADR.
- Update DESIGN.md in the same change, and link the ADR from the PROGRESS.md session log.

## Template

```markdown
# NNNN — Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD
- WP: Pn-nn

## Context
What forced the decision; evidence (spike findings, measurements).

## Decision
What we're doing.

## Consequences
What gets easier/harder; DESIGN.md / PLAN.md sections changed.

## Alternatives considered
Briefly, and why not.
```

## Index

(none yet)
