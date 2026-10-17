# VoCoder

Voice-first TUI workspace for macOS: repo tabs with Claude Code, Linear, Notion and Calendar,
fully operable by keyboard or by voice (AirPods). Swift 6 + FTXUI (C++) via an ObjC++ bridge.

## Source of truth

| File | Purpose | Changes |
|---|---|---|
| `docs/DESIGN.md` | Architecture and UX — the *what* and *why* | Rarely; with an ADR |
| `docs/PLAN.md` | Work packages (WPs), order, acceptance criteria | When scope/order changes |
| `docs/PROGRESS.md` | Live status, handoff notes, gotchas, session log | **Every session** |
| `docs/decisions/` | ADRs for decisions made after DESIGN v1 | As decisions are made |

If code and docs disagree, stop and resolve it (fix the code, or update the docs with an ADR) —
don't silently pick one.

## Session protocol

The project is built over many sessions. Context is carried by the docs above, not by memory.

**Start of session**
1. Read `docs/PROGRESS.md` (current state, next up, in-flight handoff, gotchas).
2. Read the target WP in `docs/PLAN.md` and the DESIGN.md sections it references; skim ADRs
   it touches.
3. Check `git status` / `git log -5` matches what PROGRESS.md says.
4. Post a short implementation plan for the WP (approach, files, open questions) and **wait for
   the user's go-ahead before writing code**.

**During the session**
- Work on one WP (or a few tightly related small ones). Don't start work outside the WP's scope;
  note it in PROGRESS.md instead.
- When a decision affects architecture or deviates from DESIGN.md, write an ADR and update
  DESIGN.md.
- If the WP is too big, agree a split with the user and record it in PLAN.md.

**End of session** (also before stopping mid-WP)
1. `make build` and `make test` pass (or the failure is recorded in the handoff).
2. Update `docs/PROGRESS.md`: WP status, "Current state", "Next up", in-flight handoff if
   unfinished, new gotchas, a session-log entry.
3. Commit at the end of each WP without asking (message references the WP id, e.g.
   `P1-02: …`). Mid-WP stopping points may also be committed so the handoff is clean.
   Pushing still requires asking.

## Architecture rules (see DESIGN.md §2, §4.10)

- **Extensibility is a requirement.** Integrations, agents, tabs, commands, workflows, voice
  components and brain backends are **modules** registering through protocols. Adding Jira,
  Confluence, Slack or another agent must need only a new module. If it wouldn't, fix the core
  seam first. Don't abstract seams that don't vary.
- Dependency direction: `VoCoderCore` ← modules; Core never imports a module; modules never
  import each other; only the `vocoder` executable knows concrete module types.
- Vendor-neutral domain types in Core; vendor specifics stay in adapters.
- Every protocol gets an in-memory fake and a contract test suite in `VoCoderTestSupport`.
- Every user-facing action is a registered `Command` (key binding, voice phrases, risk tier,
  spoken result). No ad-hoc key handlers.
- C++ lives only in `VoCoderUIBridge` (ObjC++ `.mm`). No Swift target enables C++ interop.
- Never write to stdout/stderr while the TUI runs; use the logging facility.

## Conventions

- Swift 6 language mode, strict concurrency, no warnings. App state is `@MainActor`; audio and
  providers run in actors/tasks.
- Tests: Swift Testing; UI via snapshot tests (`make snapshot-update` to regenerate, review the
  diff).
- Format with swift-format (`make fmt`).
- Secrets only in Keychain; never log them.
- Spikes (`spikes/`) are throwaway: findings go in `spikes/<name>/FINDINGS.md` and an ADR.

## Commands

- `make build` / `make test` (Swift Testing + `vocoder --version` smoke check) / `make run ARGS=…`
- `make pty-test` — drives the hidden `vocoder bridge-demo` (UI bridge end to end) and smoke-tests
  the app in a pty; slower
- `make snapshot-update` — regenerate UI goldens, then review the diff
- `make fmt` / `make lint` — toolchain `swift format` (`.swift-format`: 2 spaces, 100 columns);
  `lint` also runs `make check-deps` (target dependency rules, `scripts/check-deps.py`)
- `make run` — the app (no config until P1-06: Home only); `make run ARGS=--demo` — the app on
  fake modules (`DemoModule`), no accounts needed
- `make logs` — tail `~/Library/Logs/VoCoder/vocoder.log` (log via `Log(category:)` in Core)
- `make clean`; fresh clone needs `git submodule update --init` first

## Environment

macOS 26.4+ (ADR 0003), Apple Silicon, Apple Intelligence enabled; Xcode 27 / Swift 6.4; FTXUI as a git
submodule in `Vendor/FTXUI`. Supported terminals: Terminal.app (baseline), Ghostty (recommended).
