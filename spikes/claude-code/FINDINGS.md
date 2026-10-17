# P0-04 — Claude Code headless integration spike: findings

- Date: 2026-10-17 · Claude Code 2.1.302 · Swift 6.4 · macOS 26
- Run: `swift build && .build/debug/cc-spike run <scenario|all> [--model haiku|sonnet|opus] [--work DIR]`
  (scenarios: `multiturn`, `permission-host`, `permission-mcp`, `resume`, `interrupt`, `partial`,
  `todos`, `spoken`). `CC_TRACE=1` echoes every line sent and received to stderr.
  `cc-spike catalog fixtures` prints the event catalog; `cc-spike scrub fixtures --work DIR`
  re-scrubs saved transcripts.
- Each scenario runs in a fresh throwaway git repo under `--work`, never in this repo.
- Raw transcripts: `fixtures/<scenario>.out.ndjson` holds stdout verbatim and
  `fixtures/<scenario>.in.ndjson` holds what we sent. Paths, account email/organization and the
  login name are scrubbed. Per-run reports are in `results/`.

## Verdict: **GO**, using the host control protocol for permissions

One long-lived `claude -p --input-format stream-json --output-format stream-json --verbose`
process per session works well. It handles multi-turn, queued turns, permission prompts answered
by our process, interrupt, resume (also after SIGKILL) and `<spoken>` summaries. All acceptance
items pass.

The biggest change from DESIGN §4.4: **permission prompts don't need an MCP server.** With
`--permission-prompt-tool stdio` the CLI sends `can_use_tool` control requests on the same stdout
stream, and we answer on stdin. This is the same channel the Agent SDK uses. The MCP route
(`--permission-prompt-tool mcp__vocoder__approve`) also works, but it needs a second process, a
Unix socket and an MCP server, and it carries less information.

## What was built

- `ClaudeProcess` (actor): spawns `claude` via `Process` with pipes and NDJSON in both directions.
  It correlates our control requests with their `control_response`s, fails any pending request
  when stdout closes, and records the transcript.
- `Session` (`@MainActor`): consumes events turn by turn up to each `result`, and answers
  `can_use_tool` through a policy closure.
- `MCPPermission.swift`: a hand-rolled MCP stdio server (`initialize`, `ping`, `tools/list`,
  `tools/call`), run as `cc-spike mcp-permission --socket P`. It forwards each call over a Unix
  socket to the driver. This is the "vocoder binary in subcommand mode" variant from PLAN.
- `Scenarios.swift`: the scripted scenarios. `main.swift`: CLI, `catalog`, `scrub`.

## Acceptance

| Criterion | Result |
|---|---|
| A tool call requires approval, is approved by our process, completes | ✅ host protocol and MCP |
| Resume works | ✅ same `session_id`, context kept, also after SIGKILL mid-turn |
| Interrupt works | ✅ control `interrupt`, result within 7–18 ms, process stays usable |
| Fixtures saved | ✅ 15 transcripts, 1.1 MB |
| Event schema table | ✅ below |

## Measurements (Haiku unless noted)

| What | Result |
|---|---|
| Spawn → `initialize` response | ~0.55 s |
| Short turn, send → `result` | 0.8–1.0 s (first text arrives with the full block, ~10 ms before `result`) |
| Two prompts written back to back | queued and answered in order: 0.87 s, then 1.63 s |
| `can_use_tool` answer → `tool_result` event | 2–92 ms (the 92 ms included running the Bash command) |
| Interrupt → `result` | 18 ms during a tool call, 7 ms during text streaming |
| SIGINT mid-turn | process exits 0 after ~550 ms |
| Resume: spawn → answered turn | ~2.0 s |
| `<spoken>` compliance, 15 varied prompts × 3 models in one multi-turn session with tools | **45/45** present, always last, never repeated, no markdown/symbols. Words median/max: Haiku 19/40, Sonnet 23/40, Opus 16/39 |
| Turn latency median, spoken run | Haiku 2.1 s · Sonnet 3.0 s · Opus 3.6 s |

## Protocol (as observed in 2.1.302)

### Flags

```
claude -p --input-format stream-json --output-format stream-json --verbose
       --permission-prompt-tool stdio          # host answers can_use_tool (Option B)
       --permission-mode manual                # "default" in older docs; init reports "default"
       --tools Bash,Read,Write,Edit,...        # headless default set has no task tools
       --strict-mcp-config [--mcp-config F]    # keep the user's MCP servers out (or include them)
       --append-system-prompt "<spoken> instruction"
       --resume <session-id>                   # same session_id comes back in init
       --include-partial-messages              # stream_event deltas (optional)
       --model <alias>
```

Without `--permission-prompt-tool`, anything that would prompt is **denied silently**. A
`system/permission_denied` event and an `is_error` tool_result arrive, and the model just reports
the refusal. `--permission-prompts none` makes this explicit.

### Input (our stdin)

| Message | Shape |
|---|---|
| User turn | `{"type":"user","message":{"role":"user","content":"…"}}` (accepted at any time; queued while a turn runs) |
| Control request | `{"type":"control_request","request_id":"vc-N","request":{"subtype":"initialize" \| "interrupt"}}` |
| Permission answer | `{"type":"control_response","response":{"subtype":"success","request_id":"<theirs>","response":<decision>}}` |
| Decision: allow | `{"behavior":"allow","updatedInput":{…}}`. `updatedInput` is required and may be modified: the tool runs with our input (verified with Write content) |
| Decision: allow + rule | adds `"updatedPermissions":[…permission_suggestions…]`. With `"destination":"session"` it applies for the process lifetime and writes nothing; the suggested `localSettings` writes `<repo>/.claude/settings.local.json` |
| Decision: deny | `{"behavior":"deny","message":"…"}`. The message becomes the `is_error` tool_result text the model sees |

### Output (our stdout) — event schema

| type / subtype | Key fields | → `AgentEvent` |
|---|---|---|
| `control_response` (to our request) | `response.request_id`, `response.subtype`, `response.response` (`initialize`: commands, models, account, pid…; `interrupt`: `still_queued`) | resolves our request; not an event |
| `system/init` | `session_id`, `model`, `tools`, `permissionMode`, `cwd`, `mcp_servers`, `slash_commands`, `claude_code_version` | `sessionStarted(id)`. **Sent at the start of every turn**, not just once |
| `system/status` | `status` (`requesting`) | `status` (thinking / working indicator) |
| `system/thinking_tokens` | `estimated_tokens`, `estimated_tokens_delta` | `status` (optional) |
| `assistant` `[text]` | `message.id`, `message.content[].text`, `parent_tool_use_id`, `aborted?` | `text`. **One event per content block**; several share a `message.id` |
| `assistant` `[thinking]` | `thinking` (empty here, signature only) | ignore |
| `assistant` `[tool_use]` | `content[].id/name/input` | `toolUse` |
| `control_request/can_use_tool` | `request_id`, `request.tool_name`, `display_name`, `input`, `description`, `tool_use_id`, `permission_suggestions[]`, `blocked_path?` | `permissionRequest` |
| `user` `[tool_result]` | `content[].tool_use_id/content/is_error`, `tool_use_result` (structured, per tool), `tool_result_meta[].permission_decision` | `toolResult` (and `todos` for Task* tools, below) |
| `user` `[text]` | `"[Request interrupted by user]"` / `"… for tool use"` | marks an interrupt; ignore |
| `system/task_started` / `task_notification` / `task_updated` / `background_tasks_changed` | `task_id`, `tool_use_id`, `status`, `is_backgrounded`, `output_file` | `backgroundTask` (status line) |
| `system/permission_denied` | `tool_name`, `tool_use_id`, `message` | only without a permission handler |
| `stream_event` (with `--include-partial-messages`) | `event.type`: `message_start`, `content_block_start/delta/stop` (`text_delta`, `input_json_delta`), `message_delta`, `message_stop` | `textDelta` (optional, for live streaming) |
| `rate_limit_event` | `rate_limit_info.status`, `unifiedWindows.{five_hour,seven_day}.utilization`, `resetsAt` | `usage` (could feed a quota badge) |
| `result/success` | `result` (final text), `session_id`, `num_turns`, `duration_ms`, `total_cost_usd`, `usage`, `permission_denials[]`, `terminal_reason` (`completed`), `stop_reason`, `queued_turn_count`, `ttft_ms` | `turnEnd` |
| `result/error_during_execution` | `is_error`, `terminal_reason` (`aborted_tools`, `aborted_streaming`), `errors[]` | `turnEnd(interrupted)` / `error` |

The `catalog` subcommand regenerates the raw version of this table (counts and full key sets).

## Gotchas

1. **Inherited env.** When VoCoder is launched from a Claude Code session, the `CLAUDECODE`,
   `CLAUDE_CODE_*`, `CLAUDE_PID` and `AI_AGENT` vars leak into the child and make it behave as a
   nested session. Strip them when spawning.
2. **Unsolicited turns.** A command the model backgrounds (Claude Code blocks foreground
   `sleep N` and suggests backgrounding) produces a `task_notification`. When the task finishes
   the CLI **starts a new turn on its own** (`init` → assistant → `result`) without any user
   message. `AgentSession` must treat the stream as continuous, not request/response.
3. **`system/init` every turn.** Don't treat it as "session started" more than once; use the first
   one, or a changed `session_id`.
4. **Pending control requests on exit.** If the process dies (e.g. `--resume` with an unknown id:
   stderr `No conversation found…`, a `result/error_during_execution` with `errors[]`, exit 1),
   outstanding control requests are never answered. Fail them when stdout closes.
5. **Permission granularity.** Read-only shell commands (seen: `ls`, `git ls-files`)
   and the Task* tools run without prompting. Writes, redirections and `rm` prompt. Suggested
   "always" rules are narrow (`Bash(echo one *)`), and a persisted rule did **not** cover a
   repeated output redirection, which is checked separately (`blocked_path`). Session-destination
   rules did cover a repeat.
6. **`localSettings` suggestions write into the user's repo** (`.claude/settings.local.json`).
   VoCoder should default "always allow" to `destination: "session"` and offer "remember in
   repo" explicitly.
7. **No `TodoWrite` headless.** The task tools are `TaskCreate`, `TaskUpdate`, `TaskList` and
   `TaskGet`, and they're not in the default `-p` set; pass them in `--tools`. Todos come from
   `tool_use` input and `tool_use_result` (`{"task":{"id","subject"}}`,
   `{"statusChange":{"from","to"},"taskId"}`). There is no dedicated todo event.
8. **`--permission-mode`** choices are now `manual`, `acceptEdits`, `auto`, `plan`, `dontAsk` and
   `bypassPermissions`; `init` reports `manual` as `"default"`.
9. **Swift:** calling `next()` on an `AsyncStream` iterator stored in a `@MainActor` class doesn't
   compile; copy it to a local and use `next(isolation: #isolation)`. A stderr pipe must be
   drained (readabilityHandler) or a chatty child can block.
10. **Interrupt semantics.** An interrupt during a tool call kills the tool (`task_notification
    status: stopped`), and the tool_result says the user rejected it. The control response
    reports `still_queued` turns. An interrupt while idle is a harmless success.
11. **Fixture hygiene.** `initialize` returns `account.email` and `organization`, and `init` has
    `memory_paths` with mangled home paths. Scrub before committing (done here).

## Option A vs B (permission channel) and the MCP dependency

| | A: MCP permission tool | B: host control protocol |
|---|---|---|
| Moving parts | stdio MCP server process + Unix socket + config file | none beyond the existing pipe |
| Request info | `tool_name`, `input`, `tool_use_id` | adds `description`, `display_name`, `permission_suggestions`, `blocked_path` |
| "Always allow" rules | not available | `updatedPermissions` (session or settings) |
| Correlation with the stream | via `tool_use_id` across two channels | in-band, ordered with other events |
| Stability risk | MCP is a public, stable spec | control protocol is what the official Agent SDKs speak; less formally documented, could change between CLI versions |

**Recommendation: B.** It's simpler and carries more information. Keep A as a documented
fallback (the spike code proves it). To manage the stability risk, pin a minimum Claude Code
version (checked via `claude_code_version` in `init`), add contract tests that replay these
fixtures, and have `vocoder doctor` report the CLI version.

**MCP SDK:** the official `modelcontextprotocol/swift-sdk` pulls in swift-nio, swift-system,
swift-log, eventsource and swift-docc-plugin (pinned to branch `main`). That's far too heavy for one
tool. If A is ever needed, the hand-rolled server here (~60 lines) is enough. **Decision: no MCP
dependency.**

## Recommended DESIGN changes (folded into ADR 0002)

- §4.4: permission requests arrive as `can_use_tool` on the stream-json pipe
  (`--permission-prompt-tool stdio`), not via an MCP tool. `PermissionDecision` gains
  `allowOnce`, `allowForSession` (rule with destination `session`), `allowAlways` (repo settings,
  explicit), `deny(message)` and `allowEdited(input)`.
- §4.4: `AgentSession.events` is a continuous stream that can include unsolicited turns
  (background tasks). Add `AgentEvent.backgroundTask`, `.usage`, `.textDelta`; derive `todos`
  from the Task* tools.
- §4.4: env stripping, the explicit `--tools` list, and `--strict-mcp-config` as a config choice
  (whether the user's own MCP servers load inside VoCoder sessions).
- §8 risk 5 resolved.
- P1-09 scope: replay-based contract tests from `fixtures/`; minimum CLI version check.
