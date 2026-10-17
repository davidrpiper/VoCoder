# VoCoder — Design

> Status: **Draft v1** (2026-10-17). Agreed direction; Phase 0 spikes will confirm or amend the
> assumptions marked **[spike]**.

VoCoder is a voice-first TUI workspace for daily software engineering work: code repos with an AI
coding agent, task tracking, documentation and calendar, in one terminal app. It is a fully usable
keyboard-driven TUI at the desk, and fully operable by voice from across the room with AirPods.

---

## 1. Goals and non-goals

### Goals

- Do a normal engineering day — prompting Claude Code, approving its actions, triaging tickets,
  keeping up with docs and meetings — **without looking at the screen or touching the keyboard**.
- Be a **first-class TUI** when at the desk: keyboard shortcuts for everything, discoverable, fast.
- Voice and keyboard are **equal citizens**: everything reachable by one is reachable by the other.
- Use macOS-native voice and AI features (on-device speech recognition, speech synthesis,
  Foundation Models) for low latency and privacy; use Claude for heavier reasoning.
- Integrations are **pluggable**: Linear and Notion now; Jira, Confluence, Slack and other AI agents
  addable later without core changes.

### Non-goals

- Replicating full web apps (Linear, Notion, etc.) inside the TUI. VoCoder shows the slice that
  matters day-to-day and links out for the rest.
- Remote/mobile use beyond Bluetooth range of the Mac (no phone companion app for now).
- Distribution to other users: no signing, notarisation, installer or multi-user concerns.
- Cross-platform support. macOS 26+ only, Apple Silicon, Apple Intelligence enabled.

### Decisions so far

| Topic | Decision |
|---|---|
| Task tracker | Linear now; Jira later via the same `TaskTracker` protocol |
| Docs | Notion now; Confluence later via `DocsProvider` |
| Calendar | EventKit (covers Apple and Google calendars via macOS Internet Accounts) |
| Chat | Slack deferred; attention model is generic so it slots in later |
| AI agent | Claude Code (headless stream-json); `AgentBackend` protocol with stubs for others |
| Voice activation | Push-to-talk first (keyboard + AirPods); wake word optional, later |
| Cloud | Transcripts and context may be sent to Claude |
| Terminal | Terminal.app is the supported baseline; Ghostty recommended for extra features |
| UI bridge | Swift builds a declarative node tree; FTXUI renders via a small ObjC++ bridge |
| Audience | Single user (the author); local builds only |
| Extensibility | **Architectural requirement.** Every integration, agent, tab, command set, voice component and brain backend is a pluggable module behind a protocol (§4.10). Adding Jira, Confluence, Slack or another agent must not require core changes |

---

## 2. Core principles

1. **One command registry.** Every action (`tab.next`, `agent.approve`, `issue.setStatus`, …) is
   registered once with: id, title, key binding(s), voice phrases, parameters, risk tier, and a
   spoken result. Keys, the command palette, the leader-key popup, voice, and the AI brain all
   dispatch through it.
2. **Every view has a spoken representation.** Views render to both a node tree (for the screen)
   and a `Spoken` description at three levels: *glance*, *summary*, *detail*. The voice cursor
   **is** the keyboard focus — "next", "open", "read it" act on whatever is focused.
3. **A single attention queue decides when VoCoder speaks.** All events (agent needs approval,
   meeting soon, ticket assigned, doc mention) flow through one prioritised queue with one
   interruption policy.
4. **Swift is the brain; FTXUI is the renderer.** All state, logic and integrations are Swift.
   FTXUI handles layout, terminal I/O and stateful text widgets behind a narrow ObjC++ bridge.
5. **Extensible along the seams that matter.** Integrations, agents, tabs, commands, workflows,
   voice components and brain backends are contributed by **modules** through registries (§4.10).
   The core never imports anything vendor-specific; only the composition root knows concrete
   types. Seams that don't vary (e.g. the renderer) stay concrete — no speculative abstraction.

---

## 3. UX

### 3.1 Layout

```
┌─[1 Home •2]─[2 vocoder ◐]─[3 api-server ●]─[4 Linear 3]─[5 Cal 10:30 Standup]─[6 Notion 1]─┐
│                                                                                            │
│                                 active tab content                                         │
│                                                                                            │
├────────────────────────────────────────────────────────────────────────────────────────────┤
│ 🎙 LISTENING  "open the auth tic…"                  ⏵ speaking: api-server summary  queue: 2 │  voice bar
│ ^Space leader   ^P palette   ^Space v talk   ? help                                         │  hint bar
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Tab bar** (top): Home, one tab per configured repo root, then one tab per connected
  integration. Tabs show badges:
  - Repo tabs: `◐` agent working, `●` needs you (approval/question), `✓` turn finished,
    `✗` error.
  - Integration tabs: unread/attention count; Calendar shows the next event inline.
- **Voice bar**: mic state (idle / listening / thinking / speaking), live partial transcript,
  what is currently being spoken, attention-queue length.
- **Hint bar**: context-sensitive key hints.

### 3.2 Tabs

| Tab | Shows | Example voice actions |
|---|---|---|
| **Home** | Daily briefing; attention queue as a visible inbox; "review later" queue | "Good morning", "what's new?", "what needs me?" |
| **Repo** (one per root) | Agent conversation (main); side panel with git status, changed files, agent todo list, diff viewer; prompt input | "Tell Claude …", "what's it doing?", "approve" / "deny", "read the summary", "show the diff", "run the tests", "commit it", "review later" |
| **Tasks** (Linear) | My issues grouped by status, current cycle, detail pane | "What's on my plate?", "open ENG-123", "move it to in review", "comment: …", "start working on ENG-123" |
| **Calendar** | Today only: timeline, countdown to next event, join link | "What's next?", "join my meeting", "am I free at three?" |
| **Docs** (Notion) | Feed: mentions, edits to followed pages, recent publications | "Summarise that page", "read it to me", "search docs for …" |

**Cross-app workflows** are first-class commands composed from provider actions. The first one:

> **"Start working on ENG-123"** → resolve the repo (from issue/team config) → create and check out
> a branch → send the issue title/description to the agent as the opening prompt → move the issue
> to *In Progress*.

### 3.3 Keyboard

Terminals cannot see ⌘, so:

- **Leader key** `Ctrl-Space` opens a which-key style popup listing the next keys, generated from
  the command registry (e.g. `Ctrl-Space t n` = next tab, `Ctrl-Space v` = talk).
- `Ctrl-Space 1…9` jump to tabs (always works); `Alt-1…9` too where the terminal sends Option as
  Meta/Alt (not the default in Terminal.app or Ghostty — first run / `vocoder doctor` explains the
  setting; [ADR 0001](decisions/0001-ftxui-objc-bridge.md)). `Ctrl-P` opens a fuzzy command
  palette; `?` shows contextual help.
- Standard list navigation (`j/k`, arrows, `Enter`, `Esc`) in every list.
- All bindings overridable in config.

### 3.4 Voice interaction model

**Activation** (phased):

1. In-TUI push-to-talk key (toggle in Terminal.app; true hold-to-talk under Ghostty once kitty
   keyboard protocol support is added).
2. Global hold-to-talk hotkey (works regardless of focused app; needs Input Monitoring).
3. **AirPods stem press** — see §3.5.
4. Follow-up window: after VoCoder asks a question, the mic re-opens briefly for the answer.
5. Optional wake word (later).

End of utterance is detected by silence, so a second press is never required.

**Utterance routing** — three stages, cheapest first:

1. **Grammar match** (local, instant): fixed phrases from the command registry — "next tab",
   "stop", "approve", "read it", "tab three", "go to the API".
2. **Intent parse** (on-device Foundation Models, guided generation into a typed `Intent`): looser
   phrasing — "what did the last comment on my auth ticket say?"
3. **Dictation**: anything else is content for the focused context — a prompt to the agent in a
   repo tab, a comment draft on an issue.

Low-confidence results trigger a clarifying question rather than a guess. Distinct **earcons**
signal "heard a command" vs "taking dictation" vs "didn't understand".

**Barge-in**: "stop" / "skip" / "shut up" interrupt speech immediately. Requires acoustic echo
cancellation (voice-processing I/O) so VoCoder doesn't hear itself. **[spike]**

**Risk tiers** (declared per command):

| Tier | Examples | Behaviour |
|---|---|---|
| Read-only | Navigate, read, summarise | Just do it |
| Reversible | Change issue status, mark read | Do it, then "say *undo* within 5 seconds" |
| Outward / destructive | Post a comment, git push, approve an agent shell command | Read back, require explicit "confirm" |

**Spoken lists** follow screen-reader conventions: "3 of 12: ENG-123, Fix token refresh, In
Progress." Navigation commands move both the voice cursor and the visual focus.

**Making agent output listenable.** Claude Code is given an appended system prompt asking it to end
each turn with a short `<spoken>…</spoken>` summary suitable for speech. If absent, VoCoder
summarises on-device. Narration example: "Edited three files in auth. Tests pass. It wants to run
npm install — approve?"

**Honest limits.** Reviewing a diff by ear isn't realistic. "Review later" queues an item on Home
for when you're back at the screen.

### 3.5 AirPods push-to-talk **[spike]**

AirPods press-and-hold is reserved by macOS (noise control / Siri), so AirPods activation is
**press-to-start / press-to-stop** (or silence-to-stop):

| Mic state | AirPods mode | A stem press arrives as | Handled via |
|---|---|---|---|
| Idle | A2DP (high quality) | Play/pause remote command | `MPRemoteCommandCenter` while VoCoder is the Now Playing app |
| Listening | HFP (call mode) | Input mute gesture | `AVAudioApplication` input-mute state change handler |

Open questions for the spike:

- Can a terminal-launched process become the Now Playing app and receive remote commands? If not,
  this moves into a small helper app (§4.7).
- Conflict with music playback: claim play/pause only while nothing else is playing, or bind
  activation to double-press (next track) instead.
- HFP switch latency (~0.5–1.5 s): the "listening" earcon plays only once the input is live.
- Config option to use the Mac's built-in mic for input with AirPods for output only (keeps A2DP
  quality; loses the mute gesture and range).

Later: **nod to approve / shake to deny** using AirPods head tracking (`CMHeadphoneMotionManager`).

---

## 4. Architecture

```
┌──────────────────────────── vocoder (Swift 6, macOS 26+) ─────────────────────────────┐
│  App core (@MainActor state, Swift concurrency)                                        │
│   ├─ CommandRegistry  ── keys / palette / voice / brain all dispatch here              │
│   ├─ AttentionQueue   ── priority, batching, interruption policy, Focus-aware          │
│   ├─ Tabs + ViewModels ─ each produces a UI node tree + a Spoken representation        │
│   ├─ Providers        ── Git, AgentBackend, CalendarProvider, TaskTracker, DocsProvider│
│   └─ Brain            ── Foundation Models (routing, summaries) → Claude API fallback  │
│  Voice pipeline (actor)                                                                │
│   AVAudioEngine (+voice processing/AEC) → SpeechAnalyzer/SpeechTranscriber (on-device) │
│   → grammar → intent → CommandRegistry         AVSpeechSynthesizer + earcons ← queue   │
├────────────────────────── ObjC++ bridge (VoCoderUIBridge, .mm) ───────────────────────┤
│   VCRenderer: setRoot(VCNode tree), events → block callbacks; owns the FTXUI thread    │
├──────────────────────────────── FTXUI (C++20, vendored) ──────────────────────────────┤
│   App (ex-ScreenInteractive) loop on its own thread · layout · diffed terminal output │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Package layout (SwiftPM)

```
Package.swift
Vendor/FTXUI/                  git submodule, compiled as a SwiftPM C++20 target (no CMake)
Sources/
  CFTXUI/                      FTXUI sources/headers target
  VoCoderUIBridge/             ObjC++ (.mm) bridge; public headers are plain Objective-C
  VoCoderCore/                 Swift: domain types, protocols, registries, commands, attention, brain
  VoCoderTestSupport/          fakes + protocol contract test suites (test-only)
  VoCoderVoice/                Swift: audio capture, recognition, synthesis, earcons, activation
  VoCoderUI/                   Swift: node-tree DSL, focus, chrome, generic Home/Tasks/Docs tabs
  Modules/                     one target per module (§4.10)
    GitModule/
    ClaudeCodeModule/          + Codex/Gemini stub backends
    EventKitCalendarModule/
    LinearModule/
    NotionModule/
  vocoder/                     executable: composition root, CLI, module list, run loop
Tests/
  VoCoderCoreTests/            Swift Testing
  VoCoderUITests/              snapshot tests (render to off-screen ftxui::Screen → text)
  VoCoderVoiceTests/           routing tests over transcript fixtures; recognition over audio fixtures
spikes/                        throwaway Phase 0 experiments
docs/
```

Only `VoCoderUIBridge` contains C++. No Swift module enables C++ interop.

### 4.2 The FTXUI bridge

**Why ObjC++ rather than Swift's direct C++ interop:** FTXUI's API is built on `std::function`
callbacks and lambdas (Swift closures don't convert cleanly), `shared_ptr<ComponentBase>` with
virtual subclassing (not subclassable from Swift), and heavy templates. The Swift C++ interop flag
is also viral — every importing module needs it — which hurts build times and SDK imports.
Objective-C gives us blocks ↔ closures, `NSString`, ARC, and zero special flags in Swift.

**Not a 1:1 wrapper.** The bridge exposes a *render protocol*, not FTXUI's API:

- Swift builds an immutable **node tree** each update from a small vocabulary: `vbox`, `hbox`,
  `dbox`, `text`, `paragraph`, `border`, `separator`, `table`, `gauge`, `spinner`, `scrollFrame`,
  `tabBar`, `filler`, plus style (colour, bold, dim, inverted) and flex modifiers.
- C++ maps the tree to `ftxui::Element`s and renders. FTXUI provides layout, Unicode/wide-char
  width, screen diffing, input parsing and mouse support.
- **Stateful widgets** (text input with cursor/UTF-8 editing, menus, scroll positions) are real
  FTXUI components owned by C++ and keyed by a **stable id** in the node tree. Swift reads/writes
  their values through the bridge and receives change events.
- **Events** (keys, mouse, widget changes, resize) are delivered as small ObjC objects via a block
  callback; Swift hops to the main actor. Keys arrive with normalised names; the bridge also
  decodes CSI-u sequences (`ESC [ code ; mods u`, sent by Ghostty for Ctrl-I etc.), which FTXUI
  doesn't parse.
- **Ctrl-Space vs FTXUI internals:** FTXUI's `Event::Custom` and its SIGWINCH notification are
  `Special({0})` — the same byte Ctrl-Space sends. The bridge redraws with a private special
  event, never `Event::Custom`, and treats a NUL event as a resize only if the terminal size
  changed ([ADR 0001](decisions/0001-ftxui-objc-bridge.md)).
- **Ctrl-C and signals:** Ctrl-C is an ordinary key routed to the command system
  (`ForceHandleCtrlC(false)`). The app sets SIGINT/SIGTERM/SIGHUP to `SIG_IGN` and observes them
  with `DispatchSource`; FTXUI still restores the terminal and leaves its loop, and its re-raise
  of the signal is then harmless, so shutdown runs normally.

Target surface: ~10–15 ObjC classes (`VCRenderer`, `VCNode` + builders, `VCEvent`, `VCWidgetState`,
`VCStyle`, …). If a specific complex widget ever needs full FTXUI power, it can be written in C++
as a custom node type without changing the overall approach.

**Testing:** the same node → Element mapping can render to an off-screen `ftxui::Screen` and
`ToString()`, giving golden-file snapshot tests for every view.

**Escape hatch:** "pop out" suspends the TUI (`App::WithRestoredIO`) to run an
interactive program (e.g. `claude`, `$EDITOR`, `lazygit`) and resumes afterwards.

### 4.3 Threading

- **Main thread / `@MainActor`**: app state, view models, command dispatch. Keeps a live RunLoop,
  which EventKit, AVFoundation and MediaPlayer callbacks require.
- **FTXUI thread**: runs `App::Loop` (FTXUI ≥ 7.0.2; `ScreenInteractive` is now an alias). The
  loop polls input at a 60 fps cadence rather than blocking. Swift calls `[renderer setRoot:]`
  (thread-safe swap under a mutex) which posts a private redraw event via the thread-safe
  `App::PostEvent`; at most one redraw is pending, so renders coalesce (measured: 80k `setRoot`
  calls → ~90 frames; ~20 ms average latency).
- **Voice actor**: audio engine, recognition, synthesis; emits transcripts and state changes.
- **Provider tasks**: structured-concurrency tasks per provider for polling and streaming.

### 4.4 Agent integration

```swift
protocol AgentBackend {
    var id: AgentBackendID { get }
    func startSession(in repo: URL, resume: SessionID?) async throws -> AgentSession
}

protocol AgentSession: AnyObject {
    var events: AsyncStream<AgentEvent> { get }   // sessionStarted, status, text, textDelta,
                                                  // toolUse, toolResult, todos, permissionRequest,
                                                  // backgroundTask, usage, spokenSummary, turnEnd, error
    func send(_ prompt: String) async throws
    func respond(to request: PermissionRequest, _ decision: PermissionDecision) async throws
    func interrupt() async
}

// allowOnce · allowEdited(input) · allowForSession · allowAlways (repo settings, explicit only)
// · deny(message)
enum PermissionDecision { … }
```

- **`ClaudeCodeBackend`** spawns
  `claude -p --input-format stream-json --output-format stream-json --verbose
  --permission-prompt-tool stdio --permission-mode manual --tools <explicit list>` in the repo
  directory, with `--append-system-prompt` (the `<spoken>` summary instruction). Uses the existing
  Claude Code login. Validated by P0-04 ([ADR 0002](decisions/0002-claude-code-stream-json-host-permissions.md);
  event schema in `spikes/claude-code/FINDINGS.md`).
  - **Permissions** arrive in-band as `can_use_tool` control requests on stdout (tool, input,
    description, suggested rules, blocked path) and are answered on stdin. Each becomes
    `AgentEvent.permissionRequest` and is answered by keyboard or voice. "Always allow" defaults to
    a session-scoped rule; persisting to the repo's `.claude/settings.local.json` is an explicit
    choice. No MCP server is involved.
  - **Interrupt** is a control request (`interrupt`); the turn ends with an aborted `result` and the
    process stays alive. **Resume**: `--resume <session-id>`, persisted per repo tab.
  - **The event stream is continuous.** Claude Code starts turns on its own (e.g. when a background
    task finishes) and re-emits `system/init` every turn. Turns sent while one is running are
    queued.
  - **Todos** come from the `TaskCreate`/`TaskUpdate` tools (enabled via `--tools`; there is no
    `TodoWrite` headless).
  - **Spawn hygiene:** strip inherited `CLAUDECODE`/`CLAUDE_CODE_*`/`CLAUDE_PID`/`AI_AGENT` env
    vars; drain stderr to the log; fail pending control requests when stdout closes; require a
    minimum Claude Code version (from `init`). Loading the user's own MCP servers
    (`--strict-mcp-config` or not) is a config option.
- **Stubs**: `CodexBackend`, `GeminiBackend` conform to the protocol and throw
  `AgentError.notImplemented`, keeping the abstraction honest.
- One `AgentSession` per repo tab initially; multiple sessions per repo later.

### 4.5 Integration providers

All vendor code lives in provider modules. Core types are vendor-neutral.

```swift
protocol TaskTracker {                       // Linear now; Jira later
    func myIssues(filter: IssueFilter) async throws -> [Issue]
    func issue(_ key: IssueKey) async throws -> IssueDetail
    func setStatus(_ key: IssueKey, to status: StatusRef) async throws
    func comment(on key: IssueKey, body: String) async throws
    func currentIteration() async throws -> Iteration?    // Linear cycle / Jira sprint
    func changes(since: Date) async throws -> [TrackerEvent]
}

protocol DocsProvider {                      // Notion now; Confluence later
    func feed(since: Date) async throws -> [DocEvent]     // mentions, edits, publications
    func page(_ id: DocID) async throws -> DocPage        // normalised to plain text/markdown
    func search(_ query: String) async throws -> [DocRef]
}

protocol CalendarProvider {                  // EventKit
    func events(on day: Date) async throws -> [CalendarEvent]
    func changes() -> AsyncStream<Void>
}
```

- **Vendor-neutral modelling**: `Issue` has key, title, description, status (with a normalised
  category: backlog / todo / in-progress / review / done), assignee, project/team, priority,
  labels, URL. Vendor-specific status names map to categories in config, so Jira workflows fit
  later.
- **Linear**: GraphQL API with a personal API key.
- **Notion**: REST API with an internal integration token (pages must be shared with the
  integration).
- **EventKit**: Google calendars appear once the account is added in System Settings → Internet
  Accounts. Meeting links (Zoom/Meet/Teams) are extracted from location/notes.
- **Polling**: providers poll on intervals (no public webhook endpoint); diffs become events for
  the attention queue.
- **Provider actions as tools**: each provider also exposes its actions as tools to the brain
  (Foundation Models tool calling, or Claude tool use), enabling cross-app questions.

### 4.6 Brain

- **On-device (Foundation Models)**: intent parsing (guided generation into a `@Generable Intent`
  type), short summaries, briefing text. Fast, private, free.
- **Claude API**: escalation for harder cross-app questions and long-document summaries. Default
  to the latest Sonnet/Haiku models; configurable.
- Routing: grammar → on-device → Claude, with timeouts so voice never stalls.

### 4.7 Attention queue

- Every event becomes an `AttentionItem { source, priority, title, spoken, actions, expiry }`.
- **Priorities**: `interrupt` (agent needs approval, meeting in ≤2 min), `soon` (agent turn
  finished, issue assigned), `ambient` (doc edits, status changes).
- **Policy**: never interrupt while the user is speaking or dictating; batch `ambient` items into a
  digest; respect macOS Focus (if observable) and a VoCoder "quiet" mode; de-duplicate.
- **Delivery**: earcon + short spoken line; "more" / "do it" / "later" act on the item.
- Items persist on the Home tab until handled or expired.

### 4.8 Process model and permissions **[spike]**

Start as **one process** launched from the terminal. Known concerns:

- Microphone (and possibly speech/calendar) permission is attributed to the **terminal app**
  (Terminal.app or Ghostty), not VoCoder.
- Some frameworks require usage-description strings in an Info.plist. Plan: embed one in the
  binary via `-sectcreate __TEXT __info_plist`.
- Global hotkey needs Input Monitoring.

**Fallback**: a small `VoCoder Voice.app` helper (LSUIElement, no Dock icon) that owns audio
capture, speech, Now Playing / remote commands and EventKit, talking to the TUI over a Unix
socket. Adopt it only if spikes show the single-process approach is fragile.

### 4.9 Configuration and secrets

`~/.config/vocoder/config.toml`:

```toml
[voice]
input_device = "AirPods"          # or "built-in"
voice = "premium:Zoe"
airpods_activation = "single"     # single | double | off

[[repo]]
path = "~/projects/VoCoder"
aliases = ["vocoder", "the app"]

[[repo]]
path = "~/work/acme-api-server-v2"
aliases = ["the api", "api server"]
linear_teams = ["ENG"]            # used by "start working on …"

[tasks]
provider = "linear"
[tasks.status_map]
"In Review" = "review"

[docs]
provider = "notion"

[keys]
leader = "ctrl+space"
```

Secrets (Linear key, Notion token, Anthropic API key) live in the macOS Keychain, set via
`vocoder auth <provider>`.

### 4.10 Extension points and the module system

Every feature beyond the bare shell is delivered by a **module**. A module is a Swift type that
declares what it contributes; the composition root (`vocoder` executable) lists which modules are
compiled in, and config decides which are enabled.

```swift
protocol VoCoderModule {
    static var id: ModuleID { get }                    // "linear", "notion", "claude-code", …
    static var configSection: ConfigSection.Type? { get }
    init(context: ModuleContext) throws                // config, secrets, logger, services

    func register(into registry: inout ModuleRegistry) // contributes the items below
}
```

| Extension point | Registry | Contributed by (now) | Future contributors |
|---|---|---|---|
| `AgentBackend` | agents | ClaudeCode | Codex, Gemini (stubs exist) |
| `TaskTracker` | trackers | Linear | Jira |
| `DocsProvider` | docs | Notion | Confluence |
| `CalendarProvider` | calendars | EventKit | — |
| `ChatProvider` | chat | — (protocol defined, unused) | Slack |
| `TabFactory` | tabs | core (Home, Repo), each provider module | — |
| `Command` sets | commands | core + every module | — |
| `Workflow` | workflows | core ("start working on …") | per-integration workflows |
| `AttentionSource` | attention | agent, calendar, tracker, docs modules | — |
| `BrainTool` | brain tools | every provider module | — |
| `ActivationSource` | voice | keyboard PTT, global hotkey, AirPods | wake word, head gestures |
| `SpeechRecognizer` / `SpeechSynthesizer` | voice | Apple SpeechAnalyzer / AVSpeechSynthesizer | alternative engines |
| `LanguageModel` | brain | Foundation Models, Claude API | other models |

Rules:

- **Dependency direction**: `VoCoderCore` defines protocols and domain types; modules depend on
  Core; Core never depends on modules. UI for a module's tab lives in the module (depending on
  `VoCoderUI`).
- **Vendor-neutral domain types** in Core (`Issue`, `DocEvent`, `CalendarEvent`, `AgentEvent`);
  vendor detail stays inside adapters or in an opaque `vendorData` escape hatch.
- **Capabilities, not assumptions**: providers advertise optional capabilities (e.g.
  `TaskTrackerCapabilities.iterations`, `.subtasks`) so UI and commands degrade gracefully when a
  backend lacks a feature.
- **Generic tabs where possible**: the Tasks and Docs tabs are written against the protocols, so a
  Jira or Confluence module only needs an adapter, not new UI.
- **Contract tests**: each protocol ships a reusable conformance test suite in Core's test support;
  every adapter (including stubs and fakes) runs it.
- **Fakes first**: each protocol has an in-memory fake used for UI development, snapshot tests and
  demo mode (`vocoder --demo`).

---

## 5. Terminal support

| Feature | Terminal.app | Ghostty |
|---|---|---|
| Baseline rendering, 256 colour | ✓ | ✓ |
| 24-bit colour | ✓ (macOS 26) | ✓ |
| GPU rendering, smooth streaming output | — | ✓ |
| Synchronized output (no flicker) | — | ✓ |
| Kitty keyboard protocol (key release → in-TUI hold-to-talk; Ctrl-I ≠ Tab) | — | ✓ (needs FTXUI parser extension) |
| Ctrl-I distinct from Tab without negotiation (CSI u `ESC[105;5u`, decoded by bridge) | — (sends Tab) | ✓ |
| Alt-digit keys (Option as Meta/Alt) | opt-in: "Use Option as Meta key" | opt-in: `macos-option-as-alt` |

Terminal.app is the supported baseline; features degrade gracefully. Ghostty is recommended.

---

## 6. Testing strategy

- **Core**: Swift Testing unit tests for command registry, routing, attention policy, provider
  mapping (with recorded API fixtures).
- **UI**: snapshot tests rendering node trees to off-screen FTXUI screens.
- **Voice routing**: table-driven tests from transcript text → expected command/intent.
- **Recognition**: a small set of recorded audio fixtures run through SpeechAnalyzer (opt-in, slow).
- **Agent**: stream-json fixtures replayed through `ClaudeCodeBackend`'s parser.
- **Manual checklists** for audio hardware behaviour (AirPods, AEC, barge-in).

---

## 7. Roadmap

| Phase | Deliverable | Exit criteria |
|---|---|---|
| **0. Spikes** | Throwaway code in `spikes/`: (a) SwiftPM + FTXUI + ObjC++ tab bar in Terminal.app and Ghostty; (b) mic + SpeechAnalyzer + TTS permissions from a CLI, incl. AEC/barge-in; (c) AirPods stem press via Now Playing + mute gesture, HFP latency; (d) Claude Code stream-json round trip incl. permission prompts; (e) Foundation Models intent-parse accuracy over ~50 utterances | Written go/no-go per spike; this document amended. (b) and (c) run after Phase 1, before Phase 2 (see PLAN P0-07) |
| **1. Shell** | Bridge + node DSL, command registry, leader key, palette, tab bar, config, snapshot tests, Claude Code repo tab (keyboard only) | Daily-drivable for prompting Claude in one or more repos |
| **2. Voice core** | Push-to-talk (key + AirPods), recognition, grammar → intent → dictation routing, voice bar, TTS + earcons + barge-in, spoken agent summaries, voice approvals with risk tiers | A full Claude Code task done by voice from across the room |
| **3. Attention + Home + Calendar** | Attention queue + policy, Home briefing, EventKit day view, meeting reminders, "join my meeting" | Morning briefing and meeting reminders by voice |
| **4. Linear** | `TaskTracker` + Linear adapter, Tasks tab, "start working on ENG-123" | Triage and start a ticket by voice |
| **5. Notion** | `DocsProvider` + Notion adapter, Docs tab, summarise / read aloud | Hear and act on doc mentions by voice |
| **6. Hands-free polish** | Global hotkey refinements, nod/shake approvals, optional wake word, helper app if needed, kitty keyboard protocol | — |
| **Later** | Jira, Confluence, Slack providers; additional agent backends; multiple agent sessions per repo | — |

---

## 8. Open questions and risks

| # | Question / risk | Resolved by |
|---|---|---|
| 1 | Can a terminal-launched process receive AirPods remote commands as Now Playing app? | Spike (c) |
| 2 | Are TCC permissions + embedded Info.plist sufficient for Speech/EventKit from a CLI? | Spike (b) |
| 3 | AEC quality for barge-in with AirPods and built-in speakers | Spike (b) |
| 4 | Recognition and intent latency targets: <300 ms grammar, <1 s intent | Spikes (b), (e) |
| 5 | Permission prompt round-trip via `--permission-prompt-tool` in stream-json mode | ✅ Resolved: in-band host control protocol, no MCP ([ADR 0002](decisions/0002-claude-code-stream-json-host-permissions.md)) |
| 6 | Building FTXUI as a SwiftPM C++ target cleanly (no CMake) | ✅ Resolved: works, no `unsafeFlags` ([ADR 0001](decisions/0001-ftxui-objc-bridge.md)) |
| 7 | Music playback vs. play/pause activation conflict | Spike (c); config option |
| 8 | HFP audio quality drop while listening on AirPods | Accept for PTT; built-in-mic option |
