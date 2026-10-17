# VoCoder — Progress

> The live state of the project. **Read this at the start of every session; update it at the end.**
> Plan: [PLAN.md](PLAN.md) · Design: [DESIGN.md](DESIGN.md) · Decisions: [decisions/](decisions/)

## Current state

P0-01 done (2026-10-17): FTXUI v7.0.3 is a git submodule at `Vendor/FTXUI`; the bridge spike in
`spikes/ftxui-bridge/` is a **go** ([FINDINGS](../spikes/ftxui-bridge/FINDINGS.md),
[ADR 0001](decisions/0001-ftxui-objc-bridge.md)). No production code yet (no root `Package.swift`
or Makefile until P1-01).

## Next up

**P0-02 — Audio, permissions, recognition and synthesis spike** (needs the user present: mic /
speech permission prompts, speaking test phrases, AirPods). P0-04 and P0-05 can follow in any
order; P0-03 needs P0-02.

## Work package status

Status: `todo` · `in-progress` · `done` · `blocked` · `skipped`

| WP | Title | Status | Notes |
|---|---|---|---|
| P0-01 | FTXUI + ObjC++ bridge build spike | done | Go. ADR 0001 |
| P0-02 | Audio, permissions, recognition and synthesis spike | todo | |
| P0-03 | AirPods activation spike | todo | |
| P0-04 | Claude Code headless integration spike | todo | |
| P0-05 | Foundation Models intent spike | todo | |
| P0-06 | Spike synthesis | todo | |
| P1-01 | Package scaffold and tooling | todo | |
| P1-02 | UI bridge | todo | |
| P1-03 | Swift UI DSL, focus and snapshot testing | todo | |
| P1-04 | Core architecture and module system | todo | |
| P1-05 | Command system, keymap, leader key, palette | todo | |
| P1-06 | Config, secrets and CLI | todo | |
| P1-07 | App chrome | todo | |
| P1-08 | Git module | todo | |
| P1-09 | Agent backend and Claude Code module | todo | |
| P1-10 | Repo tab | todo | |
| P1-11 | M1 hardening and dogfood | todo | |
| P2-01 | Audio engine and device management | todo | |
| P2-02 | Speech recognition service | todo | |
| P2-03 | Speech output and earcons | todo | |
| P2-04 | Activation sources and voice bar | todo | |
| P2-05 | Utterance router and brain foundation | todo | |
| P2-06 | Spoken representations and voice navigation | todo | |
| P2-07 | Risk tiers, confirmation and undo | todo | |
| P2-08 | Agent voice integration | todo | |
| P2-09 | M2 tuning and dogfood | todo | |
| P3-01 | Attention queue and policy | todo | |
| P3-02 | Brain: Claude escalation and tools | todo | |
| P3-03 | Calendar module (EventKit) | todo | |
| P3-04 | Home tab and daily briefing | todo | |
| P4-01 | TaskTracker domain and polling infrastructure | todo | |
| P4-02 | Linear adapter | todo | |
| P4-03 | Tasks tab and commands | todo | |
| P4-04 | Workflow engine and "start working on" | todo | |
| P5-01 | DocsProvider and Notion adapter | todo | |
| P5-02 | Docs tab, summaries and read-aloud | todo | |
| P6-01 | Head gestures | todo | |
| P6-02 | Kitty keyboard protocol | todo | |
| P6-03 | Wake word (optional) | todo | |
| P6-04 | Helper app (conditional) | todo | |
| P6-05 | Multiple agent sessions per repo | todo | |

## In-flight handoff

_Filled in when a session ends with a WP unfinished: exact stopping point, what's half-done,
what to do next, anything uncommitted. Cleared when the WP completes._

(none)

## Known gotchas

_Durable, non-obvious lessons learned while building (toolchain quirks, API surprises). Keep each
to one or two lines; move anything architectural into an ADR._

- FTXUI 7: `ScreenInteractive` is now `App`; `component/loop.cpp` is stale and must be excluded
  (duplicate symbols); SwiftPM excludes don't glob — enumerate in `Package.swift`.
- Ctrl-Space (NUL) == FTXUI `Event::Custom` == FTXUI's SIGWINCH event. See ADR 0001.
- In `.mm` files never `using namespace ftxui;` — `MacTypes.h` declares `bold` etc.
- FTXUI re-raises SIGINT/SIGTERM/SIGHUP after restoring the terminal; `SIG_IGN` + `DispatchSource`
  makes shutdown graceful.
- In a bare pty FTXUI stalls ~500 ms at startup waiting for terminal-capability replies; use
  off-screen rendering for tests.
- Alt-digits need Option-as-Meta/Alt (off by default in Terminal.app and Ghostty); Ghostty sends
  CSI-u for Ctrl-I.

## Session log

Newest first. One entry per session: date · WP(s) · what was done · decisions · follow-ups.

### 2026-10-17 · P0-01
- Added FTXUI v7.0.3 submodule at `Vendor/FTXUI`; built `spikes/ftxui-bridge/` (SwiftPM C++20
  FTXUI target, ObjC++ `VCBridge`, Swift 6 demo with tabs, stateful input, background `setRoot`,
  off-screen render, stress mode). Pty-scripted tests for exits/signals/resize/keys; user verified
  Terminal.app and Ghostty.
- Results: go; clean build 5.7 s, 0 warnings, no `unsafeFlags`; ~20 ms redraw latency; coalescing
  and cross-thread `setRoot` safe.
- Decisions: [ADR 0001](decisions/0001-ftxui-objc-bridge.md) — private redraw event + NUL
  disambiguation for Ctrl-Space; Ctrl-C as a key and graceful signal model; CSI-u decoding;
  `Ctrl-Space 1…9` as guaranteed tab jump, Alt-digits optional. DESIGN §3.3/§4.2/§4.3/§5/§8 and
  PLAN P1-02 updated.
- Follow-ups: consider an upstream FTXUI patch giving SIGWINCH its own event; `vocoder doctor`
  should explain Option-as-Meta (P1-06/P1-07 scope).

### 2026-10-17 · planning
- Wrote DESIGN.md (v1) and PLAN.md; set up PROGRESS.md, decisions/ and CLAUDE.md session
  protocol.
- Decisions: Linear + Notion now, Jira/Confluence/Slack later as modules; Claude Code via
  headless stream-json with stub backends; AirPods push-to-talk (press-to-start/stop);
  ObjC++ node-tree bridge to FTXUI; extensibility via a module system is an architectural
  requirement.
- Follow-up: start P0-01.
- Agreed: commit at the end of each WP without asking.
