# 0002 — Claude Code via stream-json, permissions over the host control protocol

- Status: Accepted (confirmed in P0-06)
- Date: 2026-10-17
- WP: P0-04

## Context

DESIGN §4.4 planned a long-lived `claude -p` stream-json process per repo tab, with permission
prompts routed through `--permission-prompt-tool` to a VoCoder-provided MCP tool (open risk #5).
The spike (`spikes/claude-code/`, see its FINDINGS.md) drove Claude Code 2.1.302 from Swift with
scripted scenarios and saved real transcripts as fixtures.

Evidence:
- Multi-turn in one process works, and turns written mid-turn are queued in order. Short Haiku
  turns take ~0.9 s; spawn → `initialize` takes ~0.55 s.
- `--permission-prompt-tool stdio` makes the CLI send `can_use_tool` **control requests on the
  stream-json stdout**, which we answer on stdin. Allow, deny (with a message the model sees),
  allow with edited input, and session/persistent rules (`updatedPermissions`) all worked.
  Decision → tool_result took 2–92 ms.
- The MCP route also worked, via a hand-rolled stdio MCP server in subcommand mode plus a Unix
  socket. But its requests carry only `tool_name`, `input` and `tool_use_id`, with no
  description, suggestions or blocked path, and it needs a second process. The official Swift
  MCP SDK depends on swift-nio, swift-system, swift-log, eventsource and swift-docc-plugin (on
  branch `main`).
- Interrupt via control request: `result` within 7–18 ms (`terminal_reason: aborted_tools` /
  `aborted_streaming`), and the process stays usable. SIGINT exits cleanly.
- `--resume <id>` keeps the session id and context, also after SIGKILL mid-turn. An unknown id
  gives exit 1 with an error `result`.
- `<spoken>` compliance with an appended system prompt was 45/45 across Haiku, Sonnet and Opus
  (always last, plain words, median 16–23 words).
- Surprises: the CLI starts turns on its own when a backgrounded task finishes; `system/init` is
  emitted every turn; there's no `TodoWrite` headless (Task* tools must be enabled via
  `--tools`); parent Claude Code env vars leak into the child; suggested `localSettings` rules
  write into the repo's `.claude/settings.local.json`.

## Decision

- **Go** with one long-lived stream-json process per agent session, as designed.
- **Permissions use the host control protocol** (`--permission-prompt-tool stdio`), not an MCP
  tool. The MCP permission server is dropped from Phase 1. If the control protocol ever breaks,
  the spike's hand-rolled MCP server is the documented fallback.
- **No MCP SDK dependency.**
- `PermissionDecision` = `allowOnce`, `allowEdited(input)`, `allowForSession` (suggested rules
  with `destination: "session"`), `allowAlways` (repo settings, only when chosen explicitly),
  `deny(message)`.
- `AgentSession.events` is a continuous stream that can contain unsolicited turns. New event
  cases are `backgroundTask`, `usage` (rate-limit windows) and `textDelta` (optional, with
  `--include-partial-messages`). `todos` is derived from `TaskCreate`/`TaskUpdate` tool use and
  results.
- Spawn rules: strip `CLAUDECODE`, `CLAUDE_CODE_*`, `CLAUDE_PID` and `AI_AGENT` from the env; pass
  an explicit `--tools` list (including Task* tools); `--permission-mode manual`; whether to load
  the user's MCP servers (`--strict-mcp-config`) is a config option. Fail pending control requests
  when stdout closes.
- Version risk: the control protocol is what the official Agent SDKs speak but is less formally
  specified than MCP. Mitigation: a minimum Claude Code version checked against
  `claude_code_version` in `init`, fixture-replay contract tests, and a version line in
  `vocoder doctor`.

## Consequences

- Simpler: one process and one pipe per session, ordered in-band events, richer permission UI
  (description, "always allow" suggestions, blocked path).
- Harder: we depend on a less formally documented protocol, and fixtures must be re-recorded when
  Claude Code changes it.
- DESIGN.md §4.4 rewritten for the above; §8 risk 5 resolved. PLAN.md P1-09 scope updated
  (MCP bridge removed, replay contract tests, env stripping, version check); dependency table
  row "MCP server" decided (none).

## Alternatives considered

- **MCP permission tool** (`--permission-prompt-tool mcp__vocoder__approve`): works, but needs an
  extra process, a socket and an MCP server, gives poorer request info and has no rule support.
  Kept as a fallback.
- **Official Swift MCP SDK**: too heavy (swift-nio and others) for one tool.
- **`--permission-mode acceptEdits`/allowlists only**: removes prompts we want to surface by
  voice/keyboard; still available as a per-repo config choice later.
