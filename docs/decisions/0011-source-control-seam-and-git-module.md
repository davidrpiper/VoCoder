# 0011 — Source control seam, git over the CLI, and repo commands

- Status: Accepted
- Date: 2026-10-18
- WP: P1-08

## Context

P1-08 gives repo tabs their git state: status, diffs, branches, staging and commits, plus a
watcher and the refresh, checkout and commit commands. DESIGN listed "Git" among the providers,
but §4.10 had no extension point for it. Modules can't import each other, so P1-10's repo tab
(whichever module owns it) couldn't reach a `GitModule` service. The same goes for the
"start working on" workflow (P4-04), which creates branches. Commands also need to know which
repository they act on before any repo tab exists.

## Decision

- **A Core seam: `SourceControl` + `Repository`** (`VoCoderCore/SourceControl/`), registered
  through the new `sourceControl` extension point. Its models (`RepoStatus`, `ChangedFile`,
  `Branch`, `FileDiff`/`DiffHunk`/`DiffLine`, `CommitID`) and errors (`SourceControlError`) are
  neutral types, but the shape is **git's** (index vs work tree, local branches). The seam
  exists to keep the dependency direction, not to support Mercurial or jj. If another system
  comes, revisit then.
- `repository(at:)` resolves any directory inside a work tree to its top level. It returns
  **one instance per root**, so the repo tab and the commands share one watcher.
- **Git through the `git` CLI** (`GitRunner`, Foundation `Process`). No libgit2: it would be a new
  dependency (ADR 0004) and differs from the git the user and Claude Code run. Every call:
  - strips `GIT_DIR`-style variables (a parent hook's environment would point git elsewhere);
  - turns prompts, the pager and the editor off;
  - sets `GIT_OPTIONAL_LOCKS=0`, so our `status` never fights the agent over `index.lock` (and
    doesn't write the index, which would tick our own watcher);
  - passes options that pin the output format against user config: `core.quotePath=false`,
    `--src-prefix/--dst-prefix`, `--no-relative`, `--no-ext-diff`, `--no-textconv`,
    `diff.suppressBlankEmpty=false`, and `--literal-pathspecs` for user paths.

  Parsers are pure functions over porcelain v2 `-z` status, `for-each-ref` and unified diff.
  Untracked files are listed one by one (`--untracked-files=all`). An untracked path diffs as
  a new file (`--no-index`).
- **Watching**: FSEvents with file-level events on the work tree. Inside the git directory only
  HEAD, the index, refs and merge/rebase state count (objects, logs and `*.lock` don't). A git
  directory outside the work tree (linked worktrees) is watched too. Events go through a
  debouncer: 300 ms of quiet, but at most 2 s after the first event, so a long build still
  ticks. `changes()` hands out a stream per caller. The watcher runs only while someone listens.
  Ignored files (`.build/`) still tick; a status run is cheap, so they aren't filtered out.
- **Commands** `git.refresh` (read-only), `git.checkoutBranch` (reversible, undo switches back,
  can create a branch) and `git.commit` (outward). They act on, in order:
  1. a `repo` argument;
  2. the selected tab's repository: new `Tab.repo`, default nil, which P1-10's repo tab sets;
  3. the only configured repository;
  4. otherwise a choice.

  A commit with nothing staged asks to stage everything. A commit with conflicts refuses.
  There is no undo for a commit (rewriting history from an undo toast is too easy to get
  wrong).
- **Doctor**: `GitCLICheck` requires git ≥ 2.23 (`git switch`). `CLIVersion` moved from
  `ClaudeCodeModule` to Core, since both modules need it.
- **Fake and contract**: `FakeSourceControl` is a small in-memory VCS (trees, index, work
  tree, branches), so P1-10 snapshots get realistic status and diffs. `SourceControlContract`
  (with a `SourceControlFixture`) runs against it and against git on temporary repositories.
  Those repositories are isolated from the user's config (`GIT_CONFIG_GLOBAL=/dev/null`,
  `GIT_CONFIG_NOSYSTEM=1`).

## Consequences

- P1-10 finds git as `registry.sourceControl.first`. The tab needs registry access: its
  `TabContext` only has repos today, so P1-10 extends it. The tab:
  - sets `Tab.repo`;
  - observes `changes()` to refresh its side panel;
  - closes nothing (repositories are shared and live as long as the app).
- `git.refresh` only reports the status. Once the repo tab exists, it should also reload the
  panel (or the tab handles its own refresh key).
- Commits run the user's hooks (2-minute timeout). A signing setup that asks for a passphrase
  in the terminal (`pinentry-tty`) would collide with the TUI. That's not handled. GUI
  pinentry works.
- On a Mac without the Command Line Tools, `/usr/bin/git` is a shim that offers to install
  them. `vocoder doctor` reports git as missing before that matters.

## Alternatives considered

- **Repo tab inside `GitModule`**, reaching agents through the registry: ties two unrelated
  concerns into one module, and the workflow would still need a seam.
- **A service in `ServiceContainer`**: services are shared infrastructure built by the
  composition root; features modules offer go through registries (ADR 0006).
- **libgit2 / a Swift git library**: a new dependency, a second git implementation, and
  behaviour that differs from the CLI's (hooks, config, credential helpers).
- **Polling `git status`** instead of FSEvents: simpler, but either laggy or wasteful, and it
  never sees ref changes without a full status.
