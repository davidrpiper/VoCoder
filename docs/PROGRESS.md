# VoCoder — Progress

> The live state of the project. **Read this at the start of every session; update it at the end.**
> Plan: [PLAN.md](PLAN.md) · Design: [DESIGN.md](DESIGN.md) · Decisions: [decisions/](decisions/)

## Current state

P0-01 done (2026-10-17): FTXUI v7.0.3 is a git submodule at `Vendor/FTXUI`; the bridge spike in
`spikes/ftxui-bridge/` is a **go** ([FINDINGS](../spikes/ftxui-bridge/FINDINGS.md),
[ADR 0001](decisions/0001-ftxui-objc-bridge.md)).
P0-04 done (2026-10-17): Claude Code headless spike in `spikes/claude-code/` is a **go**;
permissions use the in-band host control protocol, no MCP
([FINDINGS](../spikes/claude-code/FINDINGS.md), [ADR 0002](decisions/0002-claude-code-stream-json-host-permissions.md)).
Real transcripts in `spikes/claude-code/fixtures/` (also input for P0-05 summarisation).
P0-05 done (2026-10-17): Foundation Models intent spike in `spikes/intents/` is a **go as the
guarded middle routing stage** (~70–80% on loose phrasings, ~0.8 s with prewarm; `unclear` →
Claude/clarify; model-stage risky kinds always confirm)
([FINDINGS](../spikes/intents/FINDINGS.md), [ADR 0003](decisions/0003-on-device-intent-routing.md)).
Utterance set with hold-out for P2-05: `spikes/intents/utterances.json`. Deployment target is now
macOS 26.4+.
No production code yet (no root `Package.swift` or Makefile until P1-01).

## Next up

**P0-06 — Spike synthesis (non-voice)**: review ADRs 0001/0002/0003 with the user, decide
third-party dependencies, confirm P2-05 thresholds proposed in P0-05, lock Phase 1. Voice spikes P0-02/P0-03 (+ P0-07 synthesis) are deferred
until after P1-11 because they need the user at the machine.

## Work package status

Status: `todo` · `in-progress` · `done` · `blocked` · `skipped`

| WP | Title | Status | Notes |
|---|---|---|---|
| P0-01 | FTXUI + ObjC++ bridge build spike | done | Go. ADR 0001 |
| P0-02 | Audio, permissions, recognition and synthesis spike | todo | Deferred to after P1-11 (user present) |
| P0-03 | AirPods activation spike | todo | Deferred with P0-02 |
| P0-04 | Claude Code headless integration spike | done | Go. ADR 0002 |
| P0-05 | Foundation Models intent spike | done | Go (middle stage). ADR 0003 |
| P0-06 | Spike synthesis (non-voice) | todo | P0-01/04/05 only |
| P0-07 | Voice spike synthesis | todo | After P0-02/03; gates P2-01 |
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
- Spawning `claude` from a process started inside Claude Code inherits `CLAUDECODE`/
  `CLAUDE_CODE_*` env vars → nested-session behaviour; strip them.
- `claude -p` without `--permission-prompt-tool stdio` silently denies anything that would prompt.
- Claude Code starts turns by itself when a backgrounded task finishes, and emits `system/init`
  every turn; foreground `sleep N` in Bash is blocked (use python sleep in tests).
- `initialize` response contains the account email — scrub fixtures before committing
  (`cc-spike scrub`).
- Foundation Models: `tokenCount(for:)` needs macOS 26.4; `PrivateCloudComputeLanguageModel` and
  `toolCallingMode` need macOS 27. Apple Intelligence was off on this Mac (`check` reports it).
- Foundation Models guided generation: default guardrails reject some benign utterances ("switch
  to the API") depending on schema; permissive guardrails don't help — treat as "no parse".
- Foundation Models latency spikes 4–5× under background load (e.g. right after enabling Apple
  Intelligence); compare variants back to back with a control run.
- Swift 6: `await iterator.next()` on an iterator stored in a `@MainActor` class doesn't compile;
  use a local copy with `next(isolation: #isolation)`.

## Session log

Newest first. One entry per session: date · WP(s) · what was done · decisions · follow-ups.

### 2026-10-17 · P0-05
- User enabled Apple Intelligence (was off). Built `spikes/intents/` (`intent-spike`: two schemas
  + a no-confidence variant, 5 prompt variants generated from a command catalog, tool-calling
  variant, spoken issue-key normaliser, scoring with dangerous/wrong-action metrics, fixture-based
  summariser v1/v2, context overflow probe). 83-utterance labelled set incl. 23 hold-out.
- Results: flat schema ≫ enum-with-associated-values; clean 100%, ambiguous 100%, loose ~65–80%,
  hold-out 70% (tuning +10 points on the tuning set, 0 on hold-out); one deterministic dangerous
  error ("approve the PR once CI passes" → approve); p50 1.15 s, 0.8 s with prewarm; tools harmful
  (loops to context overflow); confidence uncalibrated; guardrail false positives; on-device
  summaries usable only as `<spoken>` fallback after pre-processing.
- Decisions: [ADR 0003](decisions/0003-on-device-intent-routing.md) — guarded middle stage,
  `unclear` as the confidence signal, Claude as second interpreter (P3-02), model-stage risky
  kinds always confirm, raw utterance for dictation, context-scoped catalog, macOS 26.4+. DESIGN
  §1/§3.4/§4.6/§8 #4, PLAN P2-05/P3-02 and CLAUDE.md updated.
- Follow-ups: P0-06 confirms the P2-05 thresholds; P3-02 measures Claude on the utterance set;
  `vocoder doctor` checks Apple Intelligence availability (P1-06).

### 2026-10-17 · P0-04
- Built `spikes/claude-code/` (Swift: `ClaudeProcess` actor over stream-json pipes, `Session`
  turn consumer, hand-rolled MCP stdio permission server + Unix socket, 8 scripted scenarios,
  `catalog`/`scrub` tools). 15 scrubbed transcripts in `fixtures/`, reports in `results/`.
- Results: go. Multi-turn and queued turns work (~0.9 s Haiku turn); permissions answered
  in-band via `--permission-prompt-tool stdio` (`can_use_tool` control requests: allow, deny,
  edited input, session rules) and via MCP; interrupt → result in 7–18 ms; resume incl. after
  SIGKILL; `<spoken>` 45/45 across Haiku/Sonnet/Opus.
- Decisions: [ADR 0002](decisions/0002-claude-code-stream-json-host-permissions.md) — host control
  protocol instead of MCP for permissions; no MCP SDK dependency; richer `PermissionDecision`
  (session-scoped "always" by default); continuous event stream incl. unsolicited turns; todos
  from Task* tools. DESIGN §4.4/§8 and PLAN P1-09 + dependency table updated.
- Follow-ups: P1-09 copies fixtures into test resources and pins a minimum Claude Code version;
  P1-06 config option for loading the user's MCP servers; `vocoder doctor` reports CLI version.

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
- Plan change (user request): voice spikes P0-02/P0-03 deferred until after P1-11 (user not at
  desk for a few sessions); P0-06 now covers non-voice spikes only; new P0-07 voice synthesis
  gates P2-01. Accepted risk: a TCC/process-model surprise in P0-02 could force packaging
  changes (helper app, P6-04) after Phase 1.
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
