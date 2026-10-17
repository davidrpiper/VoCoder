# 0010 — Agent sessions: event model, transport seam, crash restart and session store

- Status: Accepted
- Date: 2026-10-17
- WP: P1-09

## Context

P1-09 builds the agent seam of DESIGN §4.4 and the Claude Code adapter that ADR 0002 validated.
DESIGN gave the protocol shape but left several things open:

- what the session reports when the agent process ends, and whether it comes back by itself;
- how to test the real session code without the real CLI, and without new dependencies;
- where a repo tab gets the id to `--resume` from;
- where the Codex/Gemini stubs live and whether they're selectable;
- ADR 0002 says strip every `CLAUDE_CODE_*` variable. Some of those configure the user's own
  account (Bedrock, Vertex, an OAuth token), not a parent session.

## Decision

- **Core API** (`VoCoderCore/Agents/`): `AgentBackend.startSession(AgentSessionOptions)`
  (repo, resume id, model) returns an `AgentSession` once the agent accepts prompts. Startup
  problems are thrown as `AgentError`: not found, too old, failed to start (including an unknown
  resume id). `AgentSession` has `events`, `send`, `respond(to:_:)`, `interrupt` and `close`.
  Tool inputs travel as Core's `JSONValue`. `PermissionRequest` is vendor-neutral. Its
  `offersSessionRule` tells the UI whether "allow for session" adds a rule; the adapter keeps
  the CLI's raw suggestions.
- **Events.** These are the cases from ADR 0002, plus `ended(AgentEndReason)` as the last event
  (`closed`, or `exited(status)` when no restart is left). `events` is one stream for the
  session's life, and `sessionStarted` comes once per session id. `text` is per content block
  and authoritative. `textDelta` streams (`--include-partial-messages` is on). Both have
  `<spoken>` removed: Core's `SpokenTag`/`SpokenTagFilter` handle it, and the summary arrives as
  `spokenSummary`. A permission request can't outlive its turn: late answers throw
  `unknownRequest`.
- **Transport seam.** `ClaudeTransport` (stdout lines, write, close input, signal, exit status,
  recent stderr) sits under `ClaudeCodeSession`.
  - `ProcessTransport` runs the real CLI. stderr goes to the log, stdin has `F_SETNOSIGPIPE`,
    and stopping escalates from end of input to SIGTERM to SIGKILL.
  - Tests inject a launcher. `ReplayTransport` (in `ModuleTests`) plays the P0-04 transcripts.
    It holds each line back until what produced it has been written, so the real mapper,
    control protocol, restart and permission paths run unchanged. The permission tests check
    that VoCoder's answers match the spike's answers JSON for JSON.
- **Crash restart.** If the process exits unexpectedly after a successful `initialize`, the
  session:
  - emits `turnEnd(failed)` if a turn was running, then `error(.crashed(status, restarting: n))`;
  - relaunches with `--resume <last session id>` up to 3 times (0.5 s, 2 s, 5 s);
  - queues prompts sent meanwhile.

  A completed turn resets the count. When the attempts run out it emits `crashed(…, nil)` and
  `ended(.exited)`. A failure before `initialize` is never retried: it's a startup error
  (bad resume id, not logged in). Control request ids (`vc-N`) are numbered per process.
- **Version check.** The backend runs `claude --version` once per executable (cached) and
  throws `unsupportedVersion` below the minimum. `system/init`'s `claude_code_version` is
  re-checked as a fallback and reported as an `error` event. The minimum stays **2.1.302**, the
  version the fixtures and the live test were verified with.
- **Env stripping** keeps `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`,
  `CLAUDE_CODE_USE_FOUNDRY` and `CLAUDE_CODE_OAUTH_TOKEN`. Every other `CLAUDE_CODE_*` variable
  is removed, as are `CLAUDECODE`, `CLAUDE_PID` and `AI_AGENT`. The doctor check uses the same
  function (`ClaudeLaunch.sanitized`).
- **Session store.** Core's `AgentSessionStore` keeps the last session id per repo and backend
  in `~/Library/Application Support/VoCoder/agent-sessions.json`. If the file can't be read or
  written, that's logged and nothing is remembered: the worst case is starting fresh. P1-10
  writes to it on `sessionStarted`; P1-11 restores from it.
- **Stubs.** `CodexBackend` and `GeminiBackend` live in `ClaudeCodeModule` (DESIGN §4.1) and
  pass `AgentBackendContract.verifyStub`. They are **not registered**, so no repo tab can pick a
  backend that only throws.
- **Fake and contracts.** `FakeAgentBackend`/`FakeAgentSession` run a scripted `Behavior` per
  prompt: `beginTurn`, `emit`, `requestPermission` (awaits the app's answer) and `endTurn`.
  They record prompts, decisions and interrupts. `AgentSessionContract` covers:
  - an interrupt while idle is harmless
  - one `sessionStarted`, before the reply
  - no `<spoken>` in text
  - `unknownRequest`
  - `close` → `ended(.closed)`, then `notRunning`

  It runs against the fake and against Claude Code over replay. `AgentEventRecorder` helps tests
  wait for events.
- **Live test.** `VOCODER_LIVE_CLAUDE=1 make test` runs Haiku in a temporary git repo: an
  approved Write, `<spoken>`, an interrupt while streaming, then a resume that remembers the
  file.

## Consequences

- P1-10 builds the repo tab on `FakeAgentBackend` for snapshots and on the registered backend
  for real use. It listens for `ended`/`crashed` to show the agent's state, and closes an open
  approval modal on `turnEnd`.
- When Claude Code changes the protocol, re-record the fixtures with the spike and copy them to
  `Tests/ModuleTests/Fixtures/claude-code/`. The replay tests then show what moved.
- A session's reader task keeps the session alive until the process ends, so owners must call
  `close()`.

## Alternatives considered

- **Testing against the real CLI only:** slow, costs quota, and isn't deterministic. It stays
  as the opt-in live test.
- **A fake `claude` script replaying fixtures:** it would test the pipes too, but would need a
  script interpreter and gating logic outside Swift. The `sh` process tests cover the pipes, and
  the in-process replay covers the protocol.
- **Restarting on any exit, including startup failures:** loops on a bad resume id or a logged-out
  CLI.
- **Registering the stubs:** they'd show up as choices that always fail.
