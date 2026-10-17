# VoCoder — Implementation Plan

> Companion to [DESIGN.md](DESIGN.md) (the *what* and *why*). This file is the *how* and *in what
> order*. Live status lives in [PROGRESS.md](PROGRESS.md); decisions made after DESIGN v1 live in
> [decisions/](decisions/).

## How this plan is used

- The work is split into **work packages (WPs)**, each sized for **one Claude session** (a few
  hours of focused work). A WP that runs long is split, and the split is recorded in PROGRESS.md.
- Each WP lists: dependencies, goal, scope, deliverables, acceptance criteria, design references
  and notes. Acceptance criteria are the definition of done *in addition to* the global
  [Definition of Done](#global-definition-of-done).
- WPs are done **in dependency order**; within a phase, independent WPs may be reordered.
- The session protocol (how to start, hand off and finish a session) is in
  [/CLAUDE.md](../CLAUDE.md).
- This plan is a living document. Changes to scope or order are made here, with a note in the
  PROGRESS.md session log and, if architectural, an ADR.

### Global Definition of Done

Every WP, unless it says otherwise:

1. `make build` succeeds with **no warnings** (Swift 6 language mode, strict concurrency).
2. `make test` passes; new logic has unit tests; new views have snapshot tests.
3. Module boundary rules (DESIGN §4.10) hold: Core imports no module; modules don't import each
   other; only the `vocoder` target knows concrete module types.
4. New protocols ship with an in-memory fake and a contract test suite in `VoCoderTestSupport`.
5. Every new user-facing action is a registered `Command` with key binding, voice phrases (from
   Phase 2 on), risk tier and spoken result.
6. No stdout/stderr output while the TUI is running; logs go through the logging facility.
7. DESIGN.md / PLAN.md updated if reality diverged; ADR written for any architectural decision.
8. PROGRESS.md updated (WP status, handoff notes, gotchas) and work committed.

### Phase overview

```
Phase 0  Spikes ─────────────► go/no-go, ADRs, DESIGN amended
Phase 1  Foundation & shell ─► M1: daily-drivable keyboard TUI with Claude Code in repo tabs
Phase 2  Voice core ─────────► M2: a full Claude Code task done by voice from across the room
Phase 3  Attention/Home/Cal ─► M3: morning briefing + meeting reminders by voice
Phase 4  Linear ─────────────► M4: triage and start a ticket by voice
Phase 5  Notion ─────────────► M5: hear and act on doc activity by voice
Phase 6  Hands-free polish ──► M6: head gestures, kitty keys, optional wake word / helper app
Later    Jira, Confluence, Slack, more agents, multi-session repos
```

### Dependency graph (WP level)

```
P0-01 ─┬─ P0-04
       └─ P0-05 ──────────────── P0-06 (synthesis of non-voice spikes; locks Phase 1)
P0-06 ─ P1-01 ─┬─ P1-02 ─ P1-03 ─┬─ P1-07 ─ P1-07b ─ P1-10 ─ P1-11
               ├─ P1-04 ─ P1-05 ─┘                   ▲
               ├─ P1-06 ──────────────────────────────┤
               ├─ P1-08 ──────────────────────────────┤
               └─ P1-09 ──────────────────────────────┘
P1-03 ─ P1-03b ─ P1-10 (markdown renderer; parallel with P1-04…P1-07)
P1-11 ─ P0-02 ─ P0-03 ─ P0-07 (voice spikes, deferred; need the user present)
P0-07 ─ P2-01 ─ P2-02 ─┬─ P2-05 ─ P2-06 ─ P2-07 ─ P2-08 ─ P2-09
        P2-03 ─────────┤
        P2-04 ─────────┘
P2-09 ─ P3-01 ─ P3-02 ─┬─ P3-03 ─ P3-04
P3-04 ─ P4-01 ─ P4-02 ─ P4-03 ─ P4-04
P4-04 ─ P5-01 ─ P5-02
P5-02 ─ P6-* (independent of each other)
```

---

## Phase 0 — Spikes

Throwaway code in `spikes/<name>/`, each a standalone SwiftPM package. Code quality bar is low;
**findings** are the deliverable. Each spike ends with `spikes/<name>/FINDINGS.md`: what was tried,
measurements, gotchas, go/no-go, and recommended changes to DESIGN.md.

### P0-01 — FTXUI + ObjC++ bridge build spike
- **Depends on:** —
- **Goal:** Prove FTXUI compiles as a SwiftPM C++20 target and is driven from Swift through an
  ObjC++ layer, without enabling Swift C++ interop.
- **Scope:** git submodule `Vendor/FTXUI` (pinned tag); SwiftPM target compiling FTXUI
  `screen`/`dom`/`component` sources; ObjC++ target exposing a toy `VCRenderer` with
  `setRoot:` taking a tiny node tree (vbox/hbox/text/border) + one stateful `Input`; Swift
  executable rendering a tab bar, switching tabs with keys, and updating content from a Swift
  timer on another thread; off-screen render to string.
- **Deliverables:** `spikes/ftxui-bridge/`, FINDINGS.md.
- **Acceptance:** runs correctly in Terminal.app and Ghostty; resize works; terminal restored on
  exit and Ctrl-C; off-screen render produces stable text; clean build time recorded.
- **Design refs:** §4.1–4.3.
- **Notes:** check FTXUI's `screen.Post`/`PostEvent` thread-safety; check whether SwiftPM needs
  `unsafeFlags` (fine for local builds); check how FTXUI handles Ctrl-Space.

### P0-02 — Audio, permissions, recognition and synthesis spike
- **Depends on:** — (**scheduled after P1-11**: needs the user at the machine for permission
  prompts, speech and AirPods; deferred 2026-10-17)
- **Goal:** Prove a terminal-launched binary can capture mic audio with echo cancellation,
  transcribe on-device with SpeechAnalyzer, speak with AVSpeechSynthesizer, and be interrupted.
- **Scope:** embedded Info.plist (`-sectcreate`); permission prompts for mic and speech
  (from Terminal.app and Ghostty); AVAudioEngine with voice processing; SpeechAnalyzer +
  SpeechTranscriber streaming partials/finals; contextual strings (custom vocabulary);
  silence-based endpointing; TTS while listening (barge-in "stop"); latency measurements.
- **Deliverables:** `spikes/voice-pipeline/`, FINDINGS.md with latency numbers (first partial,
  final after end of speech, TTS start).
- **Acceptance:** say "next tab" → recognised; say "stop" during TTS playback → TTS halts without
  self-triggering; numbers recorded for built-in mic and AirPods.
- **Design refs:** §3.4, §4.8.
- **Notes:** record which TCC permissions are attributed to which app; whether
  speech-recognition authorization is needed for SpeechAnalyzer; what breaks without Info.plist.

### P0-03 — AirPods activation spike
- **Depends on:** P0-02 (reuses its audio pipeline); scheduled with P0-02 after P1-11
- **Goal:** Determine whether AirPods stem presses can start/stop listening from a CLI process.
- **Scope:** become Now Playing (`MPNowPlayingInfoCenter`) and receive `MPRemoteCommandCenter`
  play/pause and next-track commands; `AVAudioApplication` input-mute handler during capture;
  HFP switch latency; behaviour while Music is playing; route-change handling when AirPods
  connect/disconnect; `CMHeadphoneMotionManager` quick check (nod/shake feasibility).
- **Deliverables:** `spikes/airpods/`, FINDINGS.md.
- **Acceptance:** documented answer for each mechanism (works / works with caveat / needs helper
  app / impossible) and a recommended activation design.
- **Design refs:** §3.5, §4.8.

### P0-04 — Claude Code headless integration spike
- **Depends on:** —
- **Goal:** Prove a full interactive loop with `claude -p` in stream-json mode, including
  permission prompts answered by our process.
- **Scope:** spawn with `--input-format stream-json --output-format stream-json --verbose`;
  send multiple turns into one process; parse every event type and **save real transcripts as
  fixtures**; `--permission-prompt-tool` backed by a minimal stdio MCP server (evaluate the
  official Swift MCP SDK vs a hand-rolled JSON-RPC server; the MCP server may be the `vocoder`
  binary in a subcommand mode talking back over a Unix socket); `--resume`; interrupt
  mid-turn; `--append-system-prompt` `<spoken>` compliance rate.
- **Deliverables:** `spikes/claude-code/`, fixtures, FINDINGS.md including an event schema
  table.
- **Acceptance:** a scripted session where a tool call requires approval, is approved by our
  process, and completes; resume works; interrupt works.
- **Design refs:** §4.4.

### P0-05 — Foundation Models intent spike
- **Depends on:** —
- **Goal:** Measure whether on-device intent parsing and summarisation are good and fast enough.
- **Scope:** `@Generable` `Intent` enum covering ~15 representative commands with slots;
  ~50 utterance test set (including ambiguous and dictation-like ones); accuracy and latency;
  prompt design; tool-calling check; summarisation of 3 captured agent turns (from P0-04
  fixtures if available) into speakable summaries.
- **Deliverables:** `spikes/intents/`, utterance set (kept for Phase 2 tests), FINDINGS.md.
- **Acceptance:** accuracy and p50/p95 latency recorded; recommendation on thresholds and Claude
  fallback.
- **Design refs:** §3.4, §4.6.

### P0-06 — Spike synthesis (non-voice)
- **Depends on:** P0-01, P0-04, P0-05
- **Goal:** Fold the non-voice spike findings back into the design and lock Phase 1.
- **Scope:** ADRs for each significant finding; amend DESIGN.md (especially §4.2, §4.4, §4.6);
  adjust Phase 1 WPs in this plan; decide third-party dependencies (see
  [Dependency decisions](#dependency-decisions)). Voice findings are P0-07.
- **Deliverables:** ADRs, updated DESIGN.md and PLAN.md.
- **Acceptance:** user has reviewed and confirmed the amended design.

### P0-07 — Voice spike synthesis
- **Depends on:** P0-02, P0-03 (run after P1-11)
- **Goal:** Fold voice/AirPods findings into the design and lock Phase 2.
- **Scope:** ADRs; amend DESIGN.md §3.4, §3.5, §4.8 (process model, TCC, Info.plist; pull P6-04
  helper app forward if a terminal-launched binary can't get mic/speech permission); adjust
  Phase 2 WPs.
- **Deliverables:** ADRs, updated DESIGN.md and PLAN.md.
- **Acceptance:** user has reviewed and confirmed the amended design.

---

## Phase 1 — Foundation & shell (Milestone M1)

**M1 acceptance:** VoCoder launches from the terminal with tabs for configured repos; each repo tab
runs a Claude Code session that can be prompted, shows streaming output, git status, changed files,
todos and diffs, and asks for permission approvals by keyboard; commands are reachable by leader
key and palette; sessions resume after restart; terminal is always restored.

### P1-01 — Package scaffold and tooling
- **Depends on:** P0-06
- **Goal:** The real package skeleton everything else builds into.
- **Scope:** `Package.swift` with all targets from DESIGN §4.1 (modules as empty targets);
  FTXUI submodule pinned; `Makefile` (`build`, `test`, `run`, `snapshot-update`, `fmt`, `lint`,
  `clean`); swift-format config; embedded Info.plist; logging facility (`os.Logger` + rotating
  file at `~/Library/Logs/VoCoder/`, `make logs` to tail); `vocoder --version`; README build
  instructions.
- **Deliverables:** compiling skeleton; `make test` runs one placeholder test per test target.
- **Notes:** swift-tools-version 6.2, platform `.macOS("26.4")`; FTXUI target settings from
  `spikes/ftxui-bridge/Package.swift` (excludes enumerated, no `component/loop.cpp`, no
  `unsafeFlags`); dependencies swift-argument-parser and TOMLDecoder per
  [ADR 0004](decisions/0004-third-party-dependencies.md), `Package.resolved` committed; `make fmt`/
  `make lint` use the toolchain's `swift format`. The `vocoder` executable alone uses
  `linkerSettings: .unsafeFlags` for `-sectcreate __TEXT __info_plist` (user-approved 2026-10-17;
  allowed because it is the root package).
- **Acceptance:** clean clone → `git submodule update --init && make build test` works.

### P1-02 — UI bridge (`VoCoderUIBridge`)
- **Depends on:** P1-01
- **Goal:** Production version of the ObjC++ render protocol.
- **Scope:** `VCNode` vocabulary (vbox, hbox, dbox, text, paragraph, border, separator, table,
  gauge, spinner, scrollFrame, tabBar, filler, style + flex modifiers); `VCRenderer`
  (start/stop, `setRoot:` thread-safe swap, coalesced redraws via a private event, resize,
  exit; Ctrl-C as a key, signal model per ADR 0001); key normalisation incl. CSI-u decoding and
  Ctrl-Space/NUL disambiguation;
  stateful widget registry keyed by stable ids (`input` single/multi-line, `menu`,
  scroll positions) with value get/set and change events; `VCEvent` (key, mouse, widget,
  resize); off-screen render to string; terminal restore on signals/crash; suspend/resume for
  pop-out (`WithRestoredIO`).
- **Deliverables:** bridge target + Swift-side thin tests through the public ObjC API.
- **Acceptance:** node tree renders identically on-screen and off-screen; widget state survives
  re-renders; events arrive on the Swift side; no Swift target enables C++ interop.
- **Design refs:** §4.2, §4.3; ADR 0001.
- **Notes:** start from `spikes/ftxui-bridge/` and its FINDINGS.md (gotchas 2, 4–6, 8, 9, 12).

### P1-03 — Swift UI DSL, focus and snapshot testing (`VoCoderUI`)
- **Depends on:** P1-02
- **Goal:** Ergonomic Swift way to build views, plus focus management and test harness.
- **Scope:** `View` protocol + result builder producing nodes; theme/styles (light/dark,
  semantic colours, degrade to 256 colours); focus tree with stable `FocusID`s, focus traversal,
  focus-scoped key handling; list/table views with selection; snapshot test helper
  (`assertSnapshot(view, size:)`, golden files in `Tests/<target>/__Snapshots__`,
  `make snapshot-update`); hidden `vocoder ui-gallery` for checking themes in real terminals.
- **Acceptance:** sample views snapshot-tested; focus traversal unit-tested.
- **Design refs:** §2.2, §4.2.
- **Notes:** split at the start (user, 2026-10-17): the markdown-lite renderer moved to P1-03b.
  Key handling is a responder chain of generic `UIAction`s with a temporary default key map
  that P1-05 replaces ([ADR 0005](decisions/0005-view-dsl-focus-and-key-routing.md)).

### P1-03b — Markdown-lite renderer (`VoCoderUI`)
- **Depends on:** P1-03
- **Goal:** Render agent output and docs readably.
- **Scope:** markdown-lite → views: headings, fenced code blocks (code background, no wrap),
  bulleted/numbered lists (nested), block quotes, rules, inline `**bold**`, `*italic*`,
  `` `code` ``, links shown as text. Styled inline text must still wrap, which the bridge can't
  do yet (`paragraph` takes plain text): add a `flow` node (FTXUI `hflow`) to the bridge, with
  bridge tests, and split text into styled words in Swift. Hand-written parser (ADR 0004).
- **Acceptance:** snapshot tests for each construct at two widths and both themes; wrapping of
  styled text; malformed input (unclosed fences/emphasis) renders as text, never crashes.
- **Design refs:** §3.2 (agent output, docs), §4.2.
- **Notes:** needed by P1-10 (agent conversation) and P5-02; can run in parallel with P1-04.

### P1-04 — Core architecture and module system (`VoCoderCore`)
- **Depends on:** P1-01
- **Goal:** App state model, module system and registries — the extensibility backbone.
- **Scope:** `VoCoderModule`, `ModuleContext`, `ModuleRegistry` and all registries from DESIGN
  §4.10 (empty protocols for not-yet-built seams, including `ChatProvider`; `LanguageModel`
  declared with the ADR 0003 shape: availability, prewarm, guided generation with timeout, typed
  "no parse" outcome); `AppState` on
  `@MainActor` with an observable change stream driving re-renders; tab model (`TabFactory`,
  `Tab` lifecycle, badges); service container passed through `ModuleContext`; composition root
  in `vocoder` with an explicit compiled-in module list; capability flags pattern;
  `VoCoderTestSupport` with fakes + contract test scaffolding; `--demo` mode wiring with fake
  modules.
- **Acceptance:** a fake module registers a tab, a command and an attention source and they
  appear; boundary rules enforced by target dependencies.
- **Design refs:** §2, §4.10.

### P1-05 — Command system, keymap, leader key, palette
- **Depends on:** P1-04 (UI pieces need P1-03)
- **Goal:** The single command registry and its keyboard front-ends.
- **Scope:** `Command` (id, title, category, params, key bindings, voice phrases, risk tier,
  availability predicate over context, spoken result); dispatcher with context (focused tab,
  focused item); undo hook interface; keymap with multi-key sequences and leader key; which-key
  popup; fuzzy palette (`Ctrl-P`) with parameter prompting; help overlay (`?`); user overrides
  from config.
- **Acceptance:** every built-in navigation action is a command; palette and leader find it;
  unit tests for keymap resolution and fuzzy ranking; snapshot tests for popups.
- **Design refs:** §2.1, §3.3.
- **Notes:** P1-03 left a temporary `KeyMap.defaultBindings` (key → `UIAction`) in `UIHost`;
  replace it with commands (`list.next`, `list.pageDown`, `focus.next`, `ui.activate`,
  `ui.cancel`, …) that call `UIHost.perform(_:)`, and hook the keymap in at
  `UIHost.onUnhandledKey` / key handling ([ADR 0005](decisions/0005-view-dsl-focus-and-key-routing.md)).
  Leaving a text field (it consumes printable keys) needs a command bound to Esc or the leader.
  P1-04 left a minimal `Command` (id, title, category, `perform(CommandContext)`), a
  `CommandRegistry` and `AppCore.run(_:)`; extend these (don't replace them) and route the dev
  shell's command list through the dispatcher ([ADR 0006](decisions/0006-module-system-and-tab-model.md)).
  **Done** ([ADR 0007](decisions/0007-command-system-and-keymap.md)). Agreed at plan time:
  `tab.next/previous/goto` moved here from P1-07; P1-05 defines `KeyBindingOverrides` and P1-06
  parses config into it; outward commands run without confirmation from keys/palette until a
  confirmer exists.

### P1-06 — Config, secrets and CLI
- **Depends on:** P1-04
- **Goal:** Configuration and secrets with per-module config sections.
- **Scope:** TOML config at `~/.config/vocoder/config.toml` (library decision per
  [Dependency decisions](#dependency-decisions)); typed root config + module `ConfigSection`s;
  validation with readable errors; Keychain wrapper; CLI via swift-argument-parser:
  `vocoder` (run), `vocoder auth <module>`, `vocoder config check`, `vocoder config init`,
  `vocoder --demo`, `vocoder doctor`; repo list + aliases; agent option for loading the user's
  own MCP servers into sessions (`--strict-mcp-config` or not, ADR 0002).
- **`vocoder doctor`:** checks and explains Apple Intelligence availability
  (`SystemLanguageModel.default.availability`), Claude Code CLI presence and version against the
  minimum (P1-09), terminal (Terminal.app/Ghostty) and Option-as-Meta/Alt for Alt-digit tab keys,
  config validity and Keychain secrets present per enabled module. Checks are contributed per
  module so new modules add their own.
- **Acceptance:** invalid config produces actionable errors before the TUI starts; secrets never
  appear in logs; `vocoder doctor` reports each check with a fix hint.
- **Design refs:** §4.9.
- **Notes:** `[keys]` (`leader`, `[keys.bindings]` command id → list of sequences, `[]`
  unbinds) maps onto `KeyBindingOverrides.parse(leader:bindings:)` (its errors are config
  errors), then `KeyboardController.rebuildKeymap(overrides:)`; `Keymap.issues` (unknown ids,
  shadowed sequences) belong in `vocoder doctor`. Doctor should also warn that macOS binds
  Ctrl-Space to "Select previous input source" when several input sources are enabled
  (System Settings → Keyboard → Shortcuts → Input Sources), which swallows the leader.
  Add a `theme = "auto" | "dark" | "light"` option (P1-03 defaults to `auto`:
  `Theme.automatic()` follows the macOS appearance).
  P1-04 hooks: `ModuleEnvironment.configSection` (`ConfigSectionReader`: parse a module's
  `ConfigSection` from TOML), `.enabled` (module ids from config), `.repos` (`RepoRoot`s);
  `SecretStore` protocol + `SecretStoreContract` (Keychain store goes here; `InMemorySecretStore`
  is in `VoCoderFakes`); `--demo` already exists on the root command. `vocoder doctor` can list
  `AppState.issues` / `LoadedModules.issues`.
  Since P1-07, plain `vocoder` runs the TUI (`VoCoderApp` → `AppShell`) with an
  `InMemorySecretStore` and no config: replace both here (Keychain store, `environment.repos`,
  enabled modules, `[keys]` overrides into `AppShell(…, overrides:)`, theme).
  **Done** ([ADR 0009](decisions/0009-config-secrets-and-doctor.md)). Agreed at plan time:
  every config error (module sections included) stops startup; modules are on unless listed in
  `[modules] disabled`; theme lives in `[ui] theme`; the real-Keychain contract test is opt-in
  (`VOCODER_KEYCHAIN_TESTS=1`). Also added: `DoctorCheck` extension point (+ fake, contract),
  `SecretSpec` declarations on modules (Linear `api-key`, Notion `token`),
  `SecretStore.hasSecret` (no Keychain prompt), `[claude-code] mcp_servers`, a Claude CLI
  doctor check (provisional minimum 2.1.302), `--config`/`$VOCODER_CONFIG`, and pty checks for
  an invalid config and for config reaching the app.

### P1-07 — App chrome
- **Depends on:** P1-03, P1-05
- **Goal:** The persistent frame of the app.
- **Scope:** tab bar with badges and overflow handling; voice bar (static placeholder states
  until Phase 2); hint bar driven by available commands; modal system (confirm dialog,
  text prompt, list picker) usable by commands; toasts; Home tab placeholder; tab commands
  (next/prev/goto n/goto by alias/close/reorder).
- **Acceptance:** snapshot tests at 80×24, 120×40, 200×60; tab switching via keys and palette.
- **Design refs:** §3.1.
- **Notes:** tab next/previous/goto-by-number are commands since P1-05 (`TabCommands` in Core);
  this WP adds close, reorder and go-to by alias. Compose the chrome with
  `.commandOverlays(keyboard)` (palette, help, which-key); the hint bar can use
  `KeyboardController.keyHint(for:)`; show `KeyboardController.lastFailure` as a toast; the
  confirm dialog should implement `CommandConfirmer` (set on `AppCore.dispatcher`) and be
  usable from keys and the palette. The real app sets up `KeyboardController` like `DemoApp`.
  The run loop, signal handling (incl. ignoring SIGINT while popped out) and the
  pop-out spawn helper exist in `Sources/vocoder/` (`TerminalRunLoop`, shared by `bridge-demo`
  and `ui-gallery` since P1-03; spawn helper in `BridgeDemo.swift`); move them into the app
  proper here. Panels use `ContextReader` + `containsFocus` for focus borders (see the gallery). The
  chrome replaces P1-04's temporary `DevShell` (`Sources/VoCoderUI/App/DevShell.swift`) and
  `DemoApp`'s development keys (digits, `q`); render tab content with `TabContent`, badges with
  `TabBadge.label`, and drive tabs through `AppState.select/close`. Keep `bridge-demo` while `make pty-test` uses it, or port the pty test to the
  real app and delete the demo.
  **Done** ([ADR 0008](decisions/0008-app-chrome-prompts-and-modals.md)). Agreed at plan time:
  the outward-command confirm dialog starts on Cancel (`y` confirms); closed tabs don't come
  back until restart (session restore, P1-11); Home can't be closed or moved. Also added:
  `CommandPrompter` in Core (commands ask confirm/text/choice and post notices), bridge `strip`
  node (tab bar and hint bar overflow), `Tab.isClosable`/`hintCommands`, `AppState.voice`,
  `TerminalSession` in `VoCoderUI` (run loop + `popOut`). `bridge-demo` stays; `make pty-test`
  also smoke-tests `vocoder --demo` and `vocoder`.

### P1-07b — Real-terminal UI checks (Terminal.app)
- **Depends on:** P1-07 (P1-06 for a hermetic `--config`)
- **Goal:** Automatically check what the pty tests can't: how the UI really looks and which keys
  really arrive in a real terminal.
- **Scope:** opt-in `make term-test` (never part of `make test`): `osascript` opens a Terminal.app
  window at a fixed size (rows × columns) running `vocoder --demo` (and `ui-gallery`) with a
  temporary config. It sends keys through System Events, including a real Ctrl-Space (catches
  the input-source shortcut) and Alt-digits. It reads the text with `contents of tab` and
  compares it with the off-screen render, and captures the window with `screencapture -l
  <window id>`. Assertions sample pixel colours at known cell positions (cell size = window size
  ÷ grid): tab-bar highlight, badge colours, dialog and toast placement, light and dark themes.
  Screenshots are kept in a results folder for review. Full-image diffs are not used because
  font smoothing and the cursor make them brittle.
- **Acceptance:** one command runs the checks and leaves Terminal as it found it (window
  closed). Failures name the check and the saved screenshot. The README documents the one-time
  permissions.
- **Needs the user present (first run):** macOS permission grants for Automation (Terminal),
  Accessibility (System Events keystrokes) and Screen Recording (`screencapture`) for the
  terminal or `claude` process running the script. The run takes keyboard focus while it runs.
- **Notes:** Ghostty has no comparable scripting interface and stays a manual check. Proposed by
  the user 2026-10-17 (during P1-06); do it before P1-10 so the repo tab gets these checks too.
  Done 2026-10-17: `make term-test`, plus a bridge fix for Terminal.app's DECRQSS echo. P1-10
  adds a repo-tab scenario to `scripts/term-test.py`.

### P1-08 — Git module
- **Depends on:** P1-04
- **Goal:** Repo state for repo tabs.
- **Scope:** `GitService` via `git` CLI (status porcelain v2, diff, branch list, current branch,
  create/checkout branch, stage, commit); FSEvents watcher with debounce; models for changed
  files and diff hunks; commands: refresh, checkout branch, commit (risk tier: outward).
- **Acceptance:** tested against temporary repos created in tests.
- **Design refs:** §3.2.

### P1-09 — Agent backend and Claude Code module
- **Depends on:** P1-04, P0-04 findings
- **Goal:** `AgentBackend`/`AgentSession` protocols and the Claude Code implementation.
- **Scope:** protocols + `AgentEvent` model (per P0-04 schema); `ClaudeCodeBackend` process
  management (spawn, stdin/stdout streaming, stderr to log, termination, crash restart);
  stream-json parser tested against spike fixtures (`spikes/claude-code/fixtures`, copied into
  test resources); permissions via the in-band `can_use_tool` control protocol (no MCP, per
  ADR 0002) incl. session-scoped "always allow"; env stripping; minimum Claude Code version check;
  unsolicited turns (background tasks); todos from Task* tools; resume/session persistence;
  interrupt; `<spoken>` extraction;
  `CodexBackend`/`GeminiBackend` stubs; fake backend scripting events for UI tests; contract
  test suite.
- **Acceptance:** fixture replays produce expected event sequences; live smoke test (manual,
  documented) completes an approved tool call.
- **Design refs:** §4.4.
- **Notes (from P1-06):** `ClaudeCodeModule` already has its config section
  (`ClaudeCodeConfig.mcpServers`: `none` → `--strict-mcp-config` with no servers, `user` → load
  the user's servers) and the doctor check `ClaudeCLICheck` with a provisional
  `minimumCLIVersion` of 2.1.302. Confirm or raise it with the replay tests, and reuse its env
  stripping (`CLAUDECODE`, `CLAUDE_CODE_*`) for the session process.
- **Done 2026-10-17** ([ADR 0010](decisions/0010-agent-sessions-transport-and-restart.md)):
  Core `Agents/` (protocols, `AgentEvent`, `JSONValue`, `SpokenTag`, `AgentSessionStore`);
  `ClaudeCodeBackend`/`ClaudeCodeSession` over a `ClaudeTransport` seam with crash restart;
  `FakeAgentBackend`; `AgentSessionContract`; 11 fixture replays, `sh`-scripted process tests,
  and the opt-in live test (`VOCODER_LIVE_CLAUDE=1 make test`, passing on 2.1.302). Minimum
  version stays 2.1.302. New config key `[claude-code] model`.

### P1-10 — Repo tab
- **Depends on:** P1-07, P1-08, P1-09
- **Goal:** The main working view.
- **Scope:** conversation view (streaming text, markdown-lite, tool calls collapsed with
  expand, tool results truncated, errors); prompt input (multi-line, history); side panel:
  git status, changed files, agent todos, diff viewer (scrollable, per-file); permission
  approval modal (approve once / always for session / deny, with command preview); agent
  state → tab badge; pop-out to interactive `claude --resume` and `$EDITOR`; commands for all
  of it.
- **Acceptance:** works against the fake backend in snapshot tests and against real Claude Code
  manually.
- **Design refs:** §3.2, §4.4.
- **Notes (from P1-07):** pop-out goes through `TerminalSession.popOut(_:arguments:directory:
  environment:banner:)` (in `VoCoderUI`); decide how the module reaches the session (a service
  key or a registry). The approval modal can be built on `ModalPresenter` or as its own trap
  scope; commands ask questions via `context.prompter`. Give the repo tab `hintCommands`
  (approve/deny/prompt). Closing a repo tab with a running agent probably wants a confirm.

### P1-11 — M1 hardening and dogfood
- **Depends on:** P1-10, P1-06
- **Goal:** Make M1 genuinely daily-drivable.
- **Scope:** session restore (open tabs, agent session ids, focus); performance with long
  transcripts (virtualised scrolling); resize edge cases; crash/terminal-restore audit;
  Terminal.app + Ghostty check; fix-list from a dogfood day recorded in PROGRESS.md.
- **Acceptance:** M1 acceptance criteria met; user signs off.
- **Notes:** closed tabs come back only through session restore (P1-07 has no reopen command).

---

## Phase 2 — Voice core (Milestone M2)

**M2 acceptance:** from across the room with AirPods: switch to a repo by name, dictate a prompt
to Claude, hear a spoken summary when it finishes, approve or deny a permission request by voice
(with confirmation), interrupt speech, ask "what's it doing?", and navigate lists by voice — all
mirrored on screen.

### P2-01 — Audio engine and device management (`VoCoderVoice`)
- **Depends on:** P1-11, P0-07
- **Scope:** `AudioSession` actor: AVAudioEngine with voice processing, input/output device
  selection (config: AirPods vs built-in), route change and device connect/disconnect handling,
  mic state machine (idle → arming → live → closing), level metering for the voice bar.
- **Acceptance:** state machine unit-tested with a fake audio device; manual device-switch test.

### P2-02 — Speech recognition service
- **Depends on:** P2-01
- **Scope:** `SpeechRecognizer` protocol + SpeechAnalyzer implementation: streaming partials and
  finals as an `AsyncStream`; silence endpointing (configurable); dynamic contextual vocabulary
  fed from registries (tab names, aliases, command phrases, issue keys); audio-fixture test
  harness (opt-in).
- **Acceptance:** fixture utterances transcribe correctly; vocabulary updates take effect.

### P2-03 — Speech output and earcons
- **Depends on:** P2-01
- **Scope:** `SpeechSynthesizer` protocol + AVSpeechSynthesizer implementation (voice, rate,
  pitch from config); utterance queue with priorities; immediate interrupt; earcon set
  (bundled resources: listening, command, dictation, error, attention, confirm);
  speech-friendly text normalisation (code identifiers, paths, ticket keys, numbers, emoji).
- **Acceptance:** normalisation unit-tested; interrupt latency measured.

### P2-04 — Activation sources and voice bar
- **Depends on:** P2-01
- **Scope:** `ActivationSource` protocol; in-TUI PTT key; global hotkey (event tap, Input
  Monitoring); AirPods source per P0-03; follow-up listening window; voice bar live states
  (idle/listening with partial transcript/thinking/speaking, level meter, queue length).
- **Acceptance:** each source starts/stops listening; voice bar snapshot tests per state.

### P2-05 — Utterance router and brain foundation
- **Depends on:** P2-02, P1-05
- **Scope:** grammar compiler from command voice phrases with typed slots (tab name/alias,
  number, issue key, free text) plus deterministic normalisation of spoken issue keys/numbers;
  `LanguageModel` protocol + Foundation Models implementation (availability, prewarm, guided
  generation with timeout, typed "no parse" outcome); flat `kind` + slots `@Generable` schema
  and prompt generated from the commands available in the current context; three-stage routing
  per [ADR 0003](decisions/0003-on-device-intent-routing.md) (`unclear`/errors → clarify, model-stage
  risky kinds always confirm, raw utterance for dictation); clarification dialogue ("did you
  mean …?"); dictation target resolution by context; routing test table seeded from
  `spikes/intents/utterances.json` (incl. its hold-out set).
- **Notes:** the `LanguageModel` protocol, `GenerationSchema`/`GenerationOutcome`,
  `withGenerationTimeout`, `FakeLanguageModel` and `LanguageModelContract` exist since P1-04
  (ADR 0006); this WP writes the Foundation Models adapter (neutral schema →
  `DynamicGenerationSchema`) and runs the contract against it. Compare against the spike's static
  `@Generable` numbers. Phrases, parameters (slots), risk tiers and availability come from
  `Command` (P1-05); dispatch with `source: .voice` through `CommandDispatcher`, and prompt for
  missing parameters like the palette does. The Foundation Models module also takes over
  `vocoder doctor`'s Apple Intelligence check (`DoctorCommand.appleIntelligence` in the
  executable since P1-06) as a module doctor check.
- **Acceptance (hard gates, confirmed in P0-06):** 0 unconfirmed dangerous actions; wrong-action
  rate ≤10%; grammar stage <50 ms; model p50 ≤1.0 s with prewarm; routing table ≥95% on clean
  and ≥65% on loose and hold-out utterances, with the remaining misses ending in a clarifying
  question, not an action.
- **Stretch goals:** ≥75% on loose and hold-out (the P0-05 proposal). The spike measured 62%
  loose / 65% hold-out / ~14% wrong actions for the chosen configuration, so the wrong-action
  gate depends on the guard rules (ignore undeclared slots, dictation-trap handling) and the
  loose target on the Claude fallback (P3-02).

### P2-06 — Spoken representations and voice navigation
- **Depends on:** P2-05, P2-03
- **Scope:** `Spoken` protocol (glance/summary/detail) on all existing views; voice cursor =
  focus; list reading convention ("3 of 12: …"); commands: where am I, read it, more, next,
  previous, open, back, repeat; screen and speech stay in sync.
- **Acceptance:** spoken output unit-tested per view (text, not audio).

### P2-07 — Risk tiers, confirmation and undo
- **Depends on:** P2-06
- **Scope:** confirmation flow (read-back + "confirm"/"cancel" by voice or keys); undo window for
  reversible commands; command-level undo implementations for existing commands; timeouts and
  safe defaults (no answer = cancel).
- **Acceptance:** every command's tier enforced uniformly via the dispatcher; tests for each tier.
- **Notes:** the hooks exist since P1-05: `CommandDispatcher.confirmer` (`CommandConfirmer`;
  without one, outward commands from voice/brain are declined) and `.undoSink` (`UndoSink`,
  fed by `CommandContext.offerUndo`). P1-07's dialog covers keys; this WP adds the voice flow.
  Since P1-07 the chrome's `ModalPresenter` is both the confirmer and the dispatcher's
  `CommandPrompter` (confirm/text/choice/notify, ADR 0008) for every source, voice included:
  answer its requests by voice (or compose a voice prompter with it). A read-back text per
  command (beyond title + arguments) would go on `Command`.

### P2-08 — Agent voice integration
- **Depends on:** P2-07, P1-10
- **Scope:** dictated prompts to the focused repo's agent; `<spoken>` summaries read at turn end
  (fallback on-device summariser); throttled progress narration ("still working — running
  tests"); permission requests announced and answered by voice (outward tier); "what's it
  doing?", "read the last message", "stop the agent"; "review later" queue entry.
- **Acceptance:** M2 scenario scripted against the fake backend; manual run against real Claude
  Code.

### P2-09 — M2 tuning and dogfood
- **Depends on:** P2-08
- **Scope:** latency budget audit; misrecognition log review (opt-in transcript log); phrase
  tuning; AirPods real-world test; fix-list.
- **Acceptance:** M2 acceptance met; user signs off.

---

## Phase 3 — Attention, Home, Calendar (Milestone M3)

**M3 acceptance:** "good morning" gives a spoken briefing (meetings, agent states, review-later
items); meeting reminders interrupt appropriately; "join my meeting" opens the link; the attention
queue never talks over the user.

### P3-01 — Attention queue and policy
- **Depends on:** P2-09
- **Scope:** `AttentionSource` protocol + `AttentionItem`; queue with priorities, dedupe,
  expiry, batching of ambient items into digests; interruption policy (never while
  listening/dictating; quiet mode; Focus detection if feasible); delivery via earcon + speech
  + toast; item actions ("more", "do it", "later", "dismiss"); agent module migrated to emit
  attention items.
- **Acceptance:** policy unit-tested with a virtual clock.

### P3-02 — Brain: Claude escalation and tools
- **Depends on:** P3-01
- **Scope:** Claude API `LanguageModel` implementation (key in Keychain); `BrainTool` registry
  populated by modules; cross-app question answering with escalation rules; cost/latency
  logging; Claude as second interpreter for utterances the on-device model returns as `unclear`
  (measure accuracy/latency on the P0-05 utterance set, ADR 0003).
- **Acceptance:** "what am I doing today?" answered using calendar + agent tools (fakes in
  tests); with the Claude second interpreter, routing ≥80% on loose and hold-out utterances
  while keeping P2-05's gates (0 unconfirmed dangerous, ≤10% wrong actions).

### P3-03 — Calendar module (EventKit)
- **Depends on:** P3-01
- **Scope:** `CalendarProvider` + EventKit implementation (permission, calendar selection in
  config, change notifications); meeting link extraction (Zoom/Meet/Teams); Calendar tab day
  view (timeline, now line, next-event countdown); attention items for upcoming meetings
  (configurable lead times); commands: what's next, join meeting, am I free at …
- **Acceptance:** fake-provider snapshot tests; manual check with a Google calendar via Internet
  Accounts.

### P3-04 — Home tab and daily briefing
- **Depends on:** P3-02, P3-03
- **Scope:** Home tab: briefing panel, attention inbox, review-later queue; briefing composer
  (each module contributes a briefing section via a registry); "good morning", "what's new",
  "what needs me".
- **Acceptance:** M3 acceptance met.

---

## Phase 4 — Linear (Milestone M4)

**M4 acceptance:** by voice: "what's on my plate?", open an issue and hear it summarised, change
its status, dictate a comment (confirmed), and "start working on ENG-123" performs the full
workflow.

### P4-01 — TaskTracker domain and polling infrastructure
- **Depends on:** P3-04
- **Scope:** finalise `TaskTracker` protocol, vendor-neutral `Issue`/`Status` (with categories)
  /`Iteration`/`Comment` models, capabilities; generic `Poller` (intervals, backoff, change
  detection → attention items) reusable by all providers; local cache; contract tests + fake.
- **Acceptance:** Tasks UI can be developed against the fake.

### P4-02 — Linear adapter
- **Depends on:** P4-01
- **Scope:** GraphQL client (personal API key via `vocoder auth linear`); queries (viewer's
  issues, issue detail, cycles, workflow states, comments); mutations (status, comment,
  assign); status mapping config; rate-limit handling; recorded fixtures.
- **Acceptance:** passes the `TaskTracker` contract suite with fixtures; live smoke test.

### P4-03 — Tasks tab (generic) and commands
- **Depends on:** P4-02
- **Scope:** generic Tasks tab over `TaskTracker`: grouped list, filters, detail pane
  (description markdown, comments); spoken representations; commands + voice phrases; attention
  items (assigned to me, comment on my issue, status changed).
- **Acceptance:** snapshot tests with fake; works with Linear live.

### P4-04 — Workflow engine and "start working on"
- **Depends on:** P4-03
- **Scope:** `Workflow` protocol (steps over provider protocols, progress reporting, partial
  failure + compensation); repo resolution from issue team/project config; "start working on
  <issue>" (branch, checkout, agent prompt, status change) with confirmation and spoken
  progress.
- **Acceptance:** workflow unit-tested with fakes; M4 acceptance met.

---

## Phase 5 — Notion (Milestone M5)

**M5 acceptance:** hear what changed in followed Notion pages, have a page summarised or read
aloud, and search docs by voice.

### P5-01 — DocsProvider and Notion adapter
- **Depends on:** P4-04
- **Scope:** finalise `DocsProvider` + vendor-neutral models + capabilities; Notion adapter
  (integration token; search; page + block retrieval normalised to markdown; comments); feed
  construction via polling (see note); fixtures + contract suite.
- **Notes:** the Notion public API has **no notifications/mentions inbox**. The feed must be
  derived: recently edited pages within followed pages/databases (config), new comments on
  followed pages, and mentions found by scanning comments for the user. Revisit if Notion's API
  or MCP server offers better.
- **Acceptance:** contract suite passes; feed works for a configured set of pages.

### P5-02 — Docs tab, summaries and read-aloud
- **Depends on:** P5-01
- **Scope:** generic Docs tab (feed, page reader with scroll, search); summarise (on-device,
  escalate long pages to Claude); read-aloud with section navigation ("next section", "skip");
  attention items; "send this page to Claude in <repo>" cross-module command.
- **Acceptance:** M5 acceptance met.

---

## Phase 6 — Hands-free polish (Milestone M6)

Independent WPs; order by user priority at the time.

- **P6-01 Head gestures:** `ActivationSource`-style gesture input via `CMHeadphoneMotionManager`;
  nod = confirm, shake = cancel during confirmation prompts only.
- **P6-02 Kitty keyboard protocol:** extend FTXUI input parsing (or pre-parse in the bridge) for
  key release events and disambiguated keys; true hold-to-talk in Ghostty.
- **P6-03 Wake word (optional):** evaluate on-device options; CPU/battery and privacy budget.
- **P6-04 Helper app (conditional):** only if earlier findings require it — `VoCoder Voice.app`
  owning audio/remote commands/EventKit, Unix-socket IPC.
- **P6-05 Multiple agent sessions per repo:** sub-tabs within a repo tab.

---

## Later (not yet planned in detail)

Each is expected to be **a new module only** — if it needs core changes, that's a design bug to
fix in the core first.

- Jira module (`TaskTracker`), Confluence module (`DocsProvider`).
- Slack module (`ChatProvider` + Chat tab).
- Codex / Gemini agent backends (replace stubs).

---

## Dependency decisions

Decided in P0-06 ([ADR 0004](decisions/0004-third-party-dependencies.md)). New third-party
dependencies need an ADR.

| Need | Decision |
|---|---|
| TUI rendering | FTXUI, vendored submodule ([ADR 0001](decisions/0001-ftxui-objc-bridge.md)) |
| CLI parsing | swift-argument-parser `from: "1.8.2"` |
| TOML | TOMLDecoder `from: "0.4.5"` (pure Swift, decode only) |
| MCP server (permission tool) | none — host control protocol ([ADR 0002](decisions/0002-claude-code-stream-json-host-permissions.md)) |
| GraphQL (Linear) | hand-written queries over URLSession (no codegen) |
| Snapshot testing | custom helper (off-screen render to string) |
| Logging | `os.Logger` + small rotating file sink |
| Formatting / lint | toolchain `swift format` (no SwiftLint) |
| Unit tests | Swift Testing |
