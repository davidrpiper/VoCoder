# 0013 — Repo tab: its own module, providers through `TabContext`, inline approvals

- Status: Accepted
- Date: 2026-10-18
- WP: P1-10 (P1-10a; P1-10b adds pop-outs and the diff viewer)

## Context

The repo tab (DESIGN §3.2) joins three seams: an agent backend (ADR 0010), source control
(ADR 0011) and the chrome's focus and prompts (ADR 0005, ADR 0008). Modules never import each
other, and `TabContext` only carried the repo list. The tab also needs things no tab needed
before: to move focus and edit its own text field (the prompt), to remember agent sessions, and
to answer permission requests without a second confirm dialog on every key press. In a
multi-line field Enter has to send, yet a prompt still needs newlines. Plan-time decisions
(user, 2026-10-18): split P1-10 into a and b, start the agent lazily, skip the second confirm
for keyboard approvals, and leave attention items for approvals to P3-01/P2-08.

## Decision

- **A `RepoModule` target** (Core + UI) registers one `.repo` tab factory, which makes one
  `RepoTab` per configured root, plus the `agent.*`/`repo.*` commands. It finds its agent and
  source control in the registries, never by importing `ClaudeCodeModule` or `GitModule`.
  Another agent or VCS module therefore works without changes here.
- **`TabContext` carries the registered `agents`, `sourceControl` and the shared `services`**.
  `AppCore` builds it after every module has registered. The repo tab uses the first agent and
  the first source control; choosing between several is a config key for when a second one
  exists.
- **Services**: `ServiceContainer.agentSessions` (`AgentSessionStore?`, set by the composition
  root; nil in tests remembers nothing) and `ServiceContainer.uiHost`. The latter is a weak
  `UIHostReference`, set by `AppShell` before the modules load. Tabs use it for focus requests and
  text-field contents.
- **Lazy agent**: the session starts on the tab's first `didActivate` or first prompt. It
  resumes `agentSessions.lastSession(repo:backend:)`. If resuming fails (an unknown id), the
  stored id is forgotten and a new session starts, with a notice. Prompts sent while it starts
  are queued; a failed start drops them with a "send again" footer. `sessionStarted` records the
  id. `ended` returns to "not started", so the next prompt restarts with `--resume`. `willClose`
  calls `close()`. `Tab.closeWarning` (new, default nil) makes `tab.close` confirm while a turn
  runs.
- **Conversation** is a value (`Conversation.apply(AgentEvent)`):
  - entries: prompt, message, tool call, notice, turn footer;
  - message blocks cache their `MarkdownDocument`, and only the block still streaming is
    re-parsed;
  - tool calls collect their result and approval state; a `turnEnd` drops stale approval
    requests (ADR 0010).
  The view shows tool calls as one line (`▸ Bash  git status  ✓`). The summary comes from
  generic input keys (`command`, `file_path`, …), with repo paths shown relative to the repo.
  `[`/`]` select a call, Enter expands it into an indented gutter (input, then at most 12 result
  lines), Esc returns to following the end. Sub-agent output is indented under its call.
- **Inline approval card, not a modal**: the oldest pending request is drawn above the prompt
  as a focus scope (not a trap) and gets focus when it arrives. `a`/`s`/`d`/`D` (and
  `<leader> a/s/D`) are commands that are available only while a request waits. The tab badge
  shows `●` and the hint bar lists the answers. The card disappears on answer, `turnEnd` or
  `ended`.
- **`Command.confirmsInline`**: approve/allow-for-session stay `outward`, but the card already
  reads the call back. From keys, the palette and program code the dispatcher skips its confirm;
  voice and the brain still confirm (P2-07).
- **Prompt input** (bridge): `VCNode.input(id:placeholder:submitsOnEnter:)` is a multi-line
  input where Enter submits. Alt-Enter, or Enter right after a `\` (which is removed), inserts a
  newline at the cursor. Up on the first line and Down on the last are left to the app: the tab
  walks its history through `list.up`/`list.down` (`TextField(onAction:)`), so there are no
  ad-hoc keys.
- **Leader race fix** (bridge): `VCRenderer.suspendingKey` (set to the keymap's leader). When
  that key arrives, the input thread clears the focused widget at once, so `Ctrl-Space q` read
  in one chunk quits instead of typing `q` into a focused prompt.
- **Badge**: `●` approval waiting, `◐` starting or working, `✗` failed start or error since the
  last prompt, `✓` a turn finished while the tab wasn't shown (cleared when it is).
- **Git panel**: branch with ahead/behind, changed files, agent todos; it reloads on
  `Repository.changes()`. `git.refresh` keeps only reporting the status: the watcher already
  refreshes the panel, so the tab has no refresh command of its own.
- **Demo**: `DemoModule` registers a scripted `FakeAgentBackend` (streams, asks to run a
  command, reads a file, updates todos) and a `FakeSourceControl` with a changed repo.
  `vocoder --demo` loads it with `RepoModule` over `DemoModule.repos`. The placeholder demo repo
  tab is gone.

## Consequences

- P1-10b: `TerminalHandoff` service plus `AgentBackend.interactiveLaunch` for `claude --resume`
  pop-out (close the headless session first, restart it after), `$EDITOR` (open a changed file,
  compose a prompt), the diff viewer from the changes list, and `make term-test` repo scenarios.
- Voice (P2-08) answers approvals through the same commands. They already have voice phrases,
  and voice keeps the dispatcher's confirm.
- Long transcripts re-render every entry; virtualised scrolling is P1-11.
- A second agent or VCS module would need a choice (config or per tab); today the first wins.

## Alternatives considered

- **Repo tab inside `ClaudeCodeModule` or `GitModule`**: ties the tab to one vendor; ADR 0011
  already rejected the git variant.
- **Approval through `ModalPresenter`**: a modal traps focus and stacks with unrelated
  questions, and it can't be dismissed when the turn ends without a new prompter API. It also
  hides the conversation the request is about.
- **A dispatcher rule by risk alone** (no confirm for keys): would drop the confirm for every
  outward command, `git.commit` included.
- **Ctrl-J or Shift-Enter for newlines**: Ctrl-J is the same byte as Enter after FTXUI's CR→LF
  mapping, and Terminal.app doesn't send Shift-Enter.
