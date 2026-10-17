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
P0-06 done (2026-10-17): ADRs 0001–0003 confirmed; dependencies decided
([ADR 0004](decisions/0004-third-party-dependencies.md): swift-argument-parser + TOMLDecoder only);
P2-05 hard gates vs stretch goals set; `vocoder doctor` added to P1-06. Phase 1 is locked.
P1-01 done (2026-10-17): root `Package.swift` with all DESIGN §4.1 targets (modules are empty
placeholder targets), `Makefile`, `.swift-format`, embedded Info.plist (version lives there;
`vocoder --version` reads it via `Bundle.main`), logging facility in Core (`Log` → `os.Logger` +
rotating `FileLogSink` at `~/Library/Logs/VoCoder/`).
P1-02 done (2026-10-17): production `VoCoderUIBridge` — `VCNode` (full vocabulary + modifiers),
`VCColor`, `VCEvent`, `VCKeyDecoder`, `VCRenderer` (coalesced `setRoot`, widget registry for
input/menu/scroll frame, `runSuspended:` pop-out, off-screen render, testing-only
`injectInput:`, SIGTRAP terminal restore). 45 bridge tests in `VoCoderUIBridgeTests`; hidden
`vocoder bridge-demo` + `make pty-test` (11 pty checks incl. on-screen == off-screen). The app
itself still has no TUI (`vocoder` prints a placeholder line) until P1-07.
P1-03 done (2026-10-17): `VoCoderUI` view DSL (`View` + `@ViewBuilder`, built-in views and
modifiers, `@Observable`-driven `UIHost`), themes (dark/light, `auto`), focus tree +
`FocusManager`, `UIAction` responder chain with a temporary key map, `ListView`/`TableView`/
`ScrollView`/`TextField`, `VoCoderUITestSupport.assertSnapshot`, hidden `vocoder ui-gallery`
([ADR 0005](decisions/0005-view-dsl-focus-and-key-routing.md)). Markdown renderer split off as
P1-03b.
P1-04 done (2026-10-17): module system in Core — `VoCoderModule`, `ModuleContext`
(config section, `SecretStore`, `Log`, `ServiceContainer`), `ModuleLoader` (enabled filter,
failures → `ModuleIssue`s), `ModuleRegistry` (all §4.10 extension points, unique ids, owners),
`Tab`/`TabBadge`/`TabFactory` (+ `ViewTab` in UI), `@Observable` `AppState`, `AppCore`
(tabs + attention collection + `run`), minimal `Command`/`CommandRegistry`, placeholder provider
protocols with capabilities, full `LanguageModel` (ADR 0003 shape). New `VoCoderFakes` target,
contract suites in `VoCoderTestSupport`, `DemoModule`, `ModuleTests`, `vocoder --demo` on a
temporary `DevShell`, `make check-deps` in `make lint`
([ADR 0006](decisions/0006-module-system-and-tab-model.md)).
P1-05 done (2026-10-17): command system. `Command` has key bindings, voice phrases, parameters,
risk tier, availability, spoken result and undo (via `CommandContext.say`/`offerUndo`).
`CommandDispatcher` (in `AppCore`) validates, confirms outward commands, and has an undo hook and
MRU list. `KeyChord`/`KeySequence`/`Keymap`/`KeyResolver` handle multi-key sequences and the
leader; `KeyBindingOverrides` are ready for P1-06. Also: `FuzzyMatcher`/`CommandSearch`, Core
`TabCommands` (next/prev/goto 1…9), UI `NavigationCommands` (list/focus/activate/cancel/palette/
help/quit) and `KeyboardController` (replaces `KeyMap.defaultBindings`). Overlays: which-key,
palette with parameter prompts, help (`.commandOverlays`). New bridge `clearUnder`. The demo and
the gallery run entirely on commands ([ADR 0007](decisions/0007-command-system-and-keymap.md)).
P1-07 done (2026-10-17): app chrome. `AppShell`/`AppChrome` in `VoCoderUI/Chrome/`: tab bar
(badges, overflow via the new bridge `strip` node), voice bar (static, `AppState.voice`), hint bar
(`Tab.hintCommands`), modals (`ModalPresenter`: confirm/text/list picker, also the
`CommandConfirmer`; outward commands start on Cancel, `y` confirms), toasts (`ToastCenter`),
built-in `HomeTab` (attention inbox, problems). Core: `CommandPrompter` on `CommandContext`
(+ `FakePrompter`, contract), `tab.switch/close/moveLeft/moveRight`, `Tab.isClosable`,
`AppState.move/tab(matching:)`, `AppCore(builtInTabs:)`. `TerminalSession` (run loop + `popOut`)
moved into `VoCoderUI`. `DevShell`/`DemoApp` are gone: plain `vocoder` now runs the TUI (Home
only until P1-06 brings config), `--demo` the same chrome over `DemoModule`
([ADR 0008](decisions/0008-app-chrome-prompts-and-modals.md)).

## Next up

**P1-06 — Config, secrets and CLI** (unblocked; recommended next). Plain `vocoder` now runs the
TUI with an `InMemorySecretStore` and no config: P1-06 swaps in the Keychain store, config
(repos, enabled modules, `[keys]` → `AppShell(…, overrides:)`, theme) and `vocoder doctor` (see
the PLAN notes). Then P1-08 (git) and P1-09 (agent backend), P1-03b (markdown renderer), and
P1-10 (repo tab) once those are in. All of P1-06/P1-08/P1-09/P1-03b are unblocked and
independent.
Voice spikes P0-02/P0-03 (+ P0-07) stay deferred until after P1-11 (user confirmed
2026-10-17). Keep the embedded-Info.plist and voice service boundaries easy to change
(helper-app risk). Optional user eyeball checks: `make run` / `make run ARGS=--demo` (and
`ARGS=ui-gallery`, `ARGS=bridge-demo`) in Terminal.app and Ghostty (pty tests cover behaviour,
not real-terminal looks: tab bar highlight, badge colours, toast and dialog placement). In
particular, check that `Ctrl-Space` reaches the app and isn't taken by the macOS input-source
shortcut.

## Work package status

Status: `todo` · `in-progress` · `done` · `blocked` · `skipped`

| WP | Title | Status | Notes |
|---|---|---|---|
| P0-01 | FTXUI + ObjC++ bridge build spike | done | Go. ADR 0001 |
| P0-02 | Audio, permissions, recognition and synthesis spike | todo | Deferred to after P1-11 (user present) |
| P0-03 | AirPods activation spike | todo | Deferred with P0-02 |
| P0-04 | Claude Code headless integration spike | done | Go. ADR 0002 |
| P0-05 | Foundation Models intent spike | done | Go (middle stage). ADR 0003 |
| P0-06 | Spike synthesis (non-voice) | done | ADR 0004; Phase 1 locked |
| P0-07 | Voice spike synthesis | todo | After P0-02/03; gates P2-01 |
| P1-01 | Package scaffold and tooling | done | `unsafeFlags` only on the executable (plist) |
| P1-02 | UI bridge | done | `make pty-test`; manual terminal check optional |
| P1-03 | Swift UI DSL, focus and snapshot testing | done | ADR 0005; markdown → P1-03b |
| P1-03b | Markdown-lite renderer | todo | Split from P1-03; adds bridge `flow` node |
| P1-04 | Core architecture and module system | done | ADR 0006; `vocoder --demo` |
| P1-05 | Command system, keymap, leader key, palette | done | ADR 0007; tab next/prev/goto pulled in |
| P1-06 | Config, secrets and CLI | todo | |
| P1-07 | App chrome | done | ADR 0008; `vocoder` runs the TUI |
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
- `swift test` runs each test target as its own run; grep the per-run "Test run with" lines, not
  just the last one. Log tests use temp dirs via `FileLogSink(directory:)`, never the real log.
- Swift 6: `await iterator.next()` on an iterator stored in a `@MainActor` class doesn't compile;
  use a local copy with `next(isolation: #isolation)`.
- FTXUI degrades a colour to the terminal's support when the `ftxui::Color` is *constructed*;
  support is a lazily initialised, unlocked global. `VCColor` converts at build time;
  `VCRenderer +initialize` touches it once; ANSI off-screen renders pin true colour under a mutex.
- FTXUI size constraints only act inside containers (the root always gets the whole screen);
  `Dimension::Fit` lays out at the terminal width (wrong for paragraphs off-screen).
- Foundation `Process` starts the child in a new process group: fine for `claude -p`/`git`
  (and it resets signal dispositions), wrong for interactive pop-out — use `posix_spawn` with
  `POSIX_SPAWN_SETSIGDEF` (our `SIG_IGN`s survive exec). While popped out, the tty's Ctrl-C also
  reaches vocoder's SIGINT `DispatchSource`; ignore it then.
- When a pty's session leader exits, macOS revokes the pty: the parent can't `tcgetattr` it
  afterwards. The pty test records `stty -g` from an `sh` wrapper instead.
- FTXUI's input parser reports 1-based mouse coordinates; `App` subtracts the origin.
  `injectInput:` does the same off-loop.
- Swift: `"\r\n"` is a single `Character`, so `prefix { $0 != "\r" }` never stops.
- FTXUI `size(…, EQUAL/LESS_THAN, n)` clips its child's box to n+2 cells, not n: it can't
  confine a decorator's paint area. Use a `vbox`/`hbox` with a filler instead.
- FTXUI `color(Color::Default)` is transparent (alpha 0) and blends, so it can't reset an outer
  colour; colour decorators paint their whole box before drawing the child.
- `@ViewBuilder` bodies: a primitive's `body: Never` needs an explicit `return fatalError()`,
  or the builder transform applies; the builder enum must be `@MainActor`.
- `withObservationTracking`'s `onChange` fires synchronously in `willSet` on the mutating
  thread; the host invalidates directly when that is the main thread (tests rely on it).
- pty test teardown must kill the wrapper's whole process group (`killpg`): killing only the
  `sh` wrapper orphans the demo, which never gets SIGHUP because the test still holds the pty.
- Swift Testing `#expect`: a key-path argument (`contains(where: \.isWhitespace)`) or a
  `mutating` call inside the macro doesn't compile; compute into a `let` first. Parameterised
  `@Test(arguments:)` can't read `@MainActor` statics (module metatypes) — loop instead.
- An extension `init` that forwards with a trailing closure can resolve to itself (infinite
  recursion warning) when the labels differ only in the closure; pass the closure labelled.
- `UIHost.focus.focus(id)` is deferred until the id is rendered: keys injected before the
  first `render()` reach no handler. Render first (tests and `DemoApp` do).
- `package` access works across targets of this package, test targets included; used for
  Core-only APIs that modules must go through `VoCoderUI` for (`TabFactory` init).
- macOS binds Ctrl-Space to "Select previous input source" when several input sources are
  enabled; the terminal then never sees the leader. `Alt-1…9`/`Ctrl-P` still work.
- Two `init` overloads that differ only in a closure's return type (`Void` vs a value) are
  ambiguous for multi-statement closures. Hence `Command.perform` returns `Void` and the outcome
  goes through the context.
- Trailing-closure forward scan: with two defaulted closure parameters, a trailing closure
  binds to the *first* (`isAvailable`), not `perform`. Make the last one required, or label it.
  swift-format also rejects a closure argument plus a trailing closure in Sources.
- `Task.immediate` (macOS 26) runs a command synchronously up to its first suspension: key
  presses keep their order, and tests can assert right after `type(...)`.
- FTXUI size constraints don't act on a `dbox` child at the root, and `clear_under` then clears
  the whole width. Overlays wrap their box in `hbox`/`vbox` with fillers. Borders touching
  borders below merge (`┴`).
- FTXUI's output is diff-based: a pty test can't grep a whole redrawn line after a small
  change; check for state changes instead.
- FTXUI `hbox` shrinks every text child when the row is too narrow (squashed words, not
  clipping). Rows of items that may overflow use the bridge `strip` node (`Strip` view).
- FTXUI's input widget has no Ctrl-U (kill line); tests clear a field with backspaces (`\u{7F}`).
- Swift `split(separator:)` drops empty lines by default: index screen rows with
  `omittingEmptySubsequences: false`.
- `posix_spawn_file_actions_addchdir_np` is deprecated on macOS 26; use
  `posix_spawn_file_actions_addchdir`.
- `FocusManager`: a focus request (`focus(id)`) into a trap scope that appears in the same render
  must still record the trap's return focus (fixed in P1-07; modals rely on it).

## Session log

Newest first. One entry per session: date · WP(s) · what was done · decisions · follow-ups.

### 2026-10-17 · P1-07
- Decisions (user, at plan time, as recommended): outward-command confirm dialog starts on
  Cancel (`y` confirms); closed tabs don't come back until restart (session restore, P1-11);
  Home can't be closed. Recorded with the rest in
  [ADR 0008](decisions/0008-app-chrome-prompts-and-modals.md).
- Bridge: `VCNode strip(_:keepingVisible:)` (`Strip.mm`, custom FTXUI node; window around the kept
  child, `‹n`/`n›` markers) + test.
- Core: `CommandPrompter` (`ConfirmRequest`/`TextRequest`/`ChoiceRequest`/`Notice`,
  `DecliningPrompter`), `CommandContext.prompter`, `CommandDispatcher.prompter`; `VoiceStatus` on
  `AppState.voice`; `AppState.move(_:to:)`, `tab(matching:)`; `Tab.isClosable`, `hintCommands`;
  `TabCommands` switch/close/moveLeft/moveRight; `AppCore(builtInTabs:)`.
- Fakes/contracts: `FakePrompter` (+ `PromptRequest`/`PromptAnswer`), `FakeTab` flags,
  `CommandPrompterContract` (run over the fake and `ModalPresenter`).
- UI: `Chrome/` (`AppShell`, `AppChrome`, `TabBarView`/`VoiceBarView`/`HintBarView`,
  `ModalPresenter` + `ModalCommands` + views, `ToastCenter`, `HomeTab`), `Button`, `Strip`,
  `TerminalSession` (moved from the executable, now with `popOut`), `KeyboardController.onFailure`
  (declined confirms aren't failures; messages use command titles), focus-manager trap-return
  fix. `DevShell` removed.
- App: `VoCoderApp` replaces `DemoApp`; `vocoder` runs the real modules, `--demo` the demo module;
  gallery keeps its `q` override; `bridge-demo` pops out through `TerminalSession`.
  `DemoModule`: rename (text prompt), triage (list picker + toast), publish (outward), tab hints.
- Tests: Core +6 (move/match, prompter in dispatcher, tab commands, built-in tabs, prompter
  contract); new `ChromeTests` (13: chrome at 80×24/120×40/200×60 + ANSI, overflow, voice bar
  states, hint bar, tab switching by keys and palette, close/reorder, confirm/text/picker
  modals, cancel on stop, toasts, presenter contract); `DemoModuleTests` reworked onto the
  shell; palette/help goldens gained the new tab commands. `make pty-test` 13/13 (+2 app
  checks: `--demo` chrome/leader/dialog/Ctrl-C, plain `vocoder` Home/leader quit).
- Verified: clean build 0 warnings, `make lint` clean, `make test` all runs pass, `make pty-test`
  13/13. Not done: eyeballing in Terminal.app/Ghostty (optional).
- Next: P1-06 (P1-08, P1-09, P1-03b also unblocked).

### 2026-10-17 · P1-05
- Decisions (user, at plan time, as recommended): move `tab.next/previous/goto 1…9` here from
  P1-07; P1-05 defines `KeyBindingOverrides`, P1-06 parses config into it; outward commands run
  without confirmation from keys/palette until a confirmer exists. Recorded with the rest in
  [ADR 0007](decisions/0007-command-system-and-keymap.md).
- Core (`Sources/VoCoderCore/Commands/`): `Command` (moved from `App/`, extended),
  `RiskTier`, `CommandSource`, `CommandOutcome`, `UndoAction`, `FocusSnapshot`,
  `CommandContext.say/offerUndo`, `CommandRegistry.prepend`; `CommandParameter`/`CommandValue`/
  `CommandArguments`; `CommandDispatcher` + `CommandConfirmer`/`UndoSink`; `KeyChord`,
  `KeySequence`, `KeyBinding`, `Keymap`, `KeyBindingOverrides`, `KeyResolver`; `FuzzyMatcher`,
  `CommandSearch`; `TabCommands`. `AppCore` owns the dispatcher (tab built-ins first, module
  collisions reported).
- UI: `NavigationCommands`, `KeyboardController` (keymap, leader, `Task.immediate`, palette
  stages, help, `keyHint`), `PaletteModel`, `CommandOverlays` (which-key, palette, help);
  `UIHost.onKey`, `suspendsWidgetFocus`, `focusSnapshot`, `setContent`; `clearUnder()`
  modifier. `KeyMap`/`keyMap`/`onUnhandledKey` removed.
- Bridge: `-[VCNode clearUnder]` (FTXUI `clear_under`) + test.
- App: `DemoApp`/`ui-gallery` on `KeyboardController` (gallery dev keys are commands; `q`
  added to quit via overrides); `DemoModule` commands have keys (`<leader> d …`), phrases,
  a reversible command with undo, and text/choice parameter commands.
- Tests: Core +22 (chords, keymap, resolver, overrides, conflicts, fuzzy ranking, dispatcher,
  tab commands); UI key routing reworked through commands (+2) and `CommandOverlayTests` (10, 6
  goldens: which-key ×2, palette ×3, help); `DemoModuleTests` +1 (leader, palette, prompts, quit;
  2 goldens).
- Verified: clean build 0 warnings, `make lint` clean, `make test` all runs pass,
  `make pty-test` 11/11, `vocoder --demo` driven in a pty (leader popup, `d` group, Esc, Ctrl-P,
  query, parameter prompt → note posted, `?` help, `q` quits cleanly). Not done: eyeballing
  in Terminal.app/Ghostty (optional; includes the Ctrl-Space input-source check).
- Next: P1-07 (P1-06, P1-03b, P1-08, P1-09 also unblocked).

### 2026-10-17 · P1-04
- Decisions (user, at plan time, all as recommended): tab model in Core with `ViewTab` in UI
  and `ViewTab`-only factories; fakes in a new `VoCoderFakes` target with a `DemoModule`;
  `--demo` runs a small dev shell that P1-07 replaces; minimal `Command` now, extended in P1-05.
  Recorded in [ADR 0006](decisions/0006-module-system-and-tab-model.md).
- Core: `Identifier<Kind>` typed ids; `VoCoderModule`, `ConfigSection`, `ModuleIssue`,
  `ModuleContext`, `RepoRoot`, `SecretStore`/`SecretKey`, `ServiceContainer` (`now`);
  `ModuleRegistry` (14 extension points, duplicate/empty ids rejected and attributed);
  `ModuleEnvironment`/`ModuleLoader`/`LoadedModules`; `Tab`, `TabBadge`, `TabPlacement`,
  `TabFactory`; `AppState`; `AppCore`; `Command`/`CommandContext`/`CommandRegistry`; provider
  protocols (`Provider` + agent/tracker/docs/calendar/chat/workflow/brain tool/activation/speech,
  `TaskTrackerCapabilities`); `AttentionItem`/`AttentionPriority`/`AttentionSource`;
  `LanguageModel` with `GenerationSchema` (+ validation), `GenerationOutcome`, `NoParseReason`,
  `withGenerationTimeout`.
- `VoCoderFakes` (fakes for every protocol, `FakeLanguageModel` scripted with delays,
  `FakeAttentionSource`, `InMemorySecretStore`, `FakeTab`); `VoCoderTestSupport` contract
  suites + `eventually`; `VoCoderUI`: `ViewTab`, `TabContent`, `TabBadge.label`, `DevShell`.
- Modules: the five placeholders are empty conforming modules; `DemoModule` (repo + tasks tabs,
  three commands, attention source, fake tracker and model). `vocoder`: `CompiledModules`,
  `--demo` flag, `DemoApp`.
- Tests: Core 43 (acceptance: a fake module's tab, command and attention source appear),
  UI +3, new `ModuleTests` (module contract over all six modules, demo end to end with 2
  goldens). `scripts/check-deps.py` in `make lint`; negative check confirmed it catches
  module→module and Core→UI dependencies.
  `make snapshot-update` now also regenerates `ModuleTests` goldens.
- Docs: DESIGN §4.1/§4.10/§6, PLAN notes on P1-05/P1-06/P1-07/P2-05, CLAUDE.md commands.
- Verified: clean build 0 warnings, `make lint` clean, `make test` (all runs pass),
  `make pty-test` 11/11, `vocoder --demo` driven in a pty (renders, Enter runs Ping, digit
  switches tab, `q` exits with the terminal restored). Not done: eyeballing `--demo` in
  Terminal.app/Ghostty (optional).
- Next: P1-05 (P1-03b and P1-06 are also unblocked).

### 2026-10-17 · P1-03
- Split at plan time (user): markdown-lite renderer → new P1-03b. Decisions (user): temporary
  default key map replaced by commands in P1-05; new `VoCoderUITestSupport` target; theme
  default `auto`; hidden `vocoder ui-gallery`.
- `VoCoderUI`: `View`/`ViewBuilder`/`ViewGroup`, `RenderContext`/`ContextReader`; views `Text`,
  `Paragraph`, `VStack`/`HStack`/`ZStack`, `Spacer`, `Divider`, `Gauge`, `Spinner`, `TabBar`,
  `Grid`, `TextField`, `ScrollView` (+`ScrollState`), `ListView` (+`ListState`), `TableView`;
  modifiers (style, colours, border with title/colour, frame, flex, centred, `keepVisible`);
  `Theme`/`ThemeRole`/`Appearance`; `FocusID`, `FocusTree`, `FocusManager` (nearest-survivor
  fallback, scope memory, trap scopes with return, deferred focus), `Focusable`, `focusScope`;
  `UIAction` + `KeyMap.defaultBindings`; `UIHost` (observation-driven coalesced renders, event
  routing, immediate widget-focus sync).
- Bridge: `bordered(style:title:color:)` (colours frame and title only), `VCRenderer.colorDepth`
  (class property) and `renderToString(width:height:colorDepth:)`; 2 new bridge tests.
- `vocoder`: `TerminalRunLoop` (signals + run loop) extracted from `bridge-demo`, used by both;
  `ui-gallery` (pages Theme/List/Table/Form/Layout; `t` theme, `c` colour depth, F1–F5 pages).
- Tests: 41 UI tests (DSL, theme incl. 256-colour distinctness, focus, key routing via
  `injectInput:`, lists/tables/scroll, host observation, snapshot helper) with 14 goldens.
- Docs: [ADR 0005](decisions/0005-view-dsl-focus-and-key-routing.md); DESIGN §4.1/§4.2/§6;
  PLAN P1-03 notes, new P1-03b, P1-05/P1-06/P1-07 notes.
- Verified: clean build 0 warnings, `make lint` clean, `make test` (all runs pass),
  `make pty-test` 11/11 (after the run-loop extraction), gallery smoke-tested in a pty (pages,
  activation, form submit, theme/colour toggles, quit). Not done: eyeballing the gallery in
  Terminal.app/Ghostty (optional).
- Next: P1-04 (P1-03b any time before P1-10).

### 2026-10-17 · P1-02
- Bridge split into `VCColor`/`VCNode`/`VCEvent`/`VCKeyDecoder`/`VCRenderer` `.mm` files plus
  private `BridgeInternal.h`, `BridgeState.mm` (node mapping, widget registry, root component),
  `ScrollFrame.mm` (custom viewport node), `CrashRestore.mm` (SIGTRAP). `VCBuildInfo` removed.
  Modifiers are an ordered decorator list; widget state registered on `setRoot`; Enter submits
  single-line inputs and menus; Esc/Tab/Shift-Tab/Ctrl-C/Ctrl-Space bypass focused widgets.
- Key decoder: full FTXUI table, xterm modifier params (arrows, Home/End, F-keys, `~` keys),
  CSI-u and `27;mods;code~`, Alt/Ctrl-Alt, UTF-8; 63 table-driven cases.
- `VoCoderUIBridgeTests` target (needs FTXUI's private `src/` header path only in the bridge
  target, for the input parser). `VoCoderUITests` has a placeholder until P1-03.
- `vocoder bridge-demo` (hidden; `--mouse`, `--still`, `--dump-offscreen`, `--crash-after`) and
  `scripts/bridge-pty-test.py` (`make pty-test`): q/Ctrl-C/SIGINT/SIGTERM/SIGHUP exits restore
  the terminal; on-screen == off-screen at 80×24, 100×30, 60×20; keys; mouse opt-in; input;
  pop-out with Ctrl-C inside; SIGTRAP restore. Negative checks confirmed the pop-out and SIGTRAP
  checks fail without the fixes.
- Decisions (user, at plan time): mouse off by default with an option; demo as hidden
  subcommand; `injectInput:` public, testing-only. No ADR: within ADR 0001; DESIGN §4.1/§4.2
  updated (scroll frame, colours, SIGTRAP, pop-out process rule, testing). PLAN P1-07 note: move
  run loop/signals/pop-out helper from the demo into the app.
- Verified: clean build 0 warnings, `make lint` clean, `make test`, `make pty-test` 11/11. Not
  done: manual check in Terminal.app/Ghostty (optional, user not required).
- Next: P1-03.
- Follow-up (same day): stray `bridge-demo` processes from interrupted runs traced to pty test
  teardown killing only the `sh` wrapper; now `killpg`s the group. Verified mid-pop-out teardown
  leaves nothing (old script leaked the demo); `make pty-test` 11/11.

### 2026-10-17 · P1-01
- Root package: `CFTXUI` (spike settings), `VoCoderUIBridge` (probe rendering off-screen),
  `VoCoderCore`, `VoCoderUI`, `VoCoderVoice`, `VoCoderTestSupport`, five module targets under
  `Sources/Modules/`, `vocoder` executable (swift-argument-parser), three test targets.
  TOMLDecoder attached to Core (unused until P1-06). `Package.resolved` committed.
- Logging: `Log(category:)` writes to unified log (subsystem `dev.vocoder`) and the shared sink
  installed by `Log.bootstrap`; sink rotates at 5 MB keeping 3 files, local ISO 8601 timestamps,
  `Mutex`-guarded synchronous writes. Tests cover format, level filter, rotation, append,
  concurrency.
- Info.plist embedded via `-sectcreate` (`unsafeFlags` on the executable, user-approved);
  bundle id `dev.vocoder.VoCoder`, mic/speech/calendar usage strings; `make test` smoke-checks
  `vocoder --version`. Plist edits do trigger a relink.
- Verified: clean build 0 warnings, `make lint` clean, clean clone → `git submodule update --init
  && make build test` passes.
- Next: P1-02.

### 2026-10-17 · P0-06
- Reviewed ADRs 0001–0003 with the user; 0002/0003 now plain Accepted. Checked candidate
  packages (swift-argument-parser 1.8.2; TOMLDecoder 0.4.5 pure Swift; TOMLKit wraps C++) and that
  the toolchain's `swift format` works.
- Decisions: [ADR 0004](decisions/0004-third-party-dependencies.md) — only swift-argument-parser
  and TOMLDecoder; toolchain `swift format`, Swift Testing, own logging sink and snapshot helper;
  new dependencies need an ADR. P2-05: hard gates (0 unconfirmed dangerous, ≤10% wrong actions,
  grammar <50 ms, model p50 ≤1.0 s, ≥95% clean, ≥65% loose/hold-out) with the P0-05 proposal
  (≥75% loose/hold-out) as stretch; ≥80% moves to P3-02 with Claude as second interpreter.
- PLAN: P1-01 notes (tools 6.2, macOS 26.4, FTXUI settings, deps, `Package.resolved`); P1-04
  declares `LanguageModel` with the ADR 0003 shape; P1-06 gains `vocoder doctor` (module-contributed
  checks) and the MCP-servers agent option; P1-09 kept whole (split when started if it runs
  long); dependency table final. DESIGN §4 diagram (26.4+) and §4.9 updated.
- User asked whether the AirPods/voice checks should come before Phase 1; offered to pull
  P0-02/P0-03 forward, user chose to keep them deferred until after P1-11. Next: P1-01.

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
