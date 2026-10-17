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

- [0001 — FTXUI via SwiftPM + ObjC++ bridge: validated, with key/signal rules](0001-ftxui-objc-bridge.md) (P0-01, Accepted)
- [0002 — Claude Code via stream-json, permissions over the host control protocol](0002-claude-code-stream-json-host-permissions.md) (P0-04, Accepted)
- [0003 — On-device intent parsing as a guarded middle stage](0003-on-device-intent-routing.md) (P0-05, Accepted)
- [0004 — Third-party dependencies for Phase 1](0004-third-party-dependencies.md) (P0-06, Accepted)
- [0005 — View DSL, focus tree and key routing](0005-view-dsl-focus-and-key-routing.md) (P1-03, Accepted)
- [0006 — Module system, tab model split and fakes target](0006-module-system-and-tab-model.md) (P1-04, Accepted)
