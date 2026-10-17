# VoCoder

An all-inclusive TUI workspace application that enables voice-first interaction
with my daily work applications. Essentially a voice-first IDE that will also
incorporate applications like Jira/Linear, Slack, Confluence/Notion, etc.

## Building

Requirements: macOS 26.4+ on Apple Silicon, Xcode 27 (Swift 6.4 toolchain).

```sh
git clone --recurse-submodules <repo-url> VoCoder   # or: git submodule update --init
cd VoCoder
make build test
make run                                            # pass arguments with ARGS="--version"
```

| Command | What it does |
|---|---|
| `make build` | `swift build` (FTXUI is compiled from the `Vendor/FTXUI` submodule) |
| `make test` | Swift Testing suites + a `vocoder --version` smoke check |
| `make pty-test` | Drives the hidden `vocoder bridge-demo` in a pty: UI bridge end to end (slower) |
| `make term-test` | Real-terminal checks in Terminal.app windows (opt-in; see below) |
| `make run` | Runs `vocoder` (`ARGS=bridge-demo` shows the UI bridge demo) |
| `make snapshot-update` | Regenerates UI snapshot goldens (review the diff) |
| `make fmt` / `make lint` | Toolchain `swift format` (lint is `--strict`) |
| `make logs` | Tails `~/Library/Logs/VoCoder/vocoder.log` |
| `make clean` | Removes build products |

## Real-terminal checks (`make term-test`)

`make test` and `make pty-test` never touch a real terminal. `make term-test` does: it opens
Terminal.app windows running `vocoder --demo` and `vocoder ui-gallery` and sends real keystrokes.
It compares each window's text with the app's off-screen render and checks screenshot colours
cell by cell. Each window uses a temporary Terminal profile that is deleted afterwards. Your
profiles and windows aren't changed.

- **It takes keyboard focus** for about two minutes. Don't type or switch windows while it runs.
- **One-time permissions**, granted to the app that runs `make` (Terminal, Ghostty, …) under
  System Settings › Privacy & Security:
  - **Automation**: allow it to control *Terminal* and *System Events*. macOS asks on the first
    run.
  - **Accessibility**: for System Events keystrokes. Add the app, then switch it on.
  - **Screen Recording**: for `screencapture`. Quit and reopen the app after granting it.
- **Results:** screenshots and text dumps per step go to `.build/term-test/<timestamp>/`.
  A failure names the check and its screenshot. `ARGS="-k gallery"` runs matching scenarios
  only; `ARGS=--keep` leaves a failed window open.
- **Warnings** aren't failures. For example, Ctrl-Space doesn't reach the app when macOS binds
  it to "Select previous input source" (`vocoder doctor` explains).

## Docs

- [Design](docs/DESIGN.md) — architecture and UX
- [Plan](docs/PLAN.md) — work packages and milestones
- [Progress](docs/PROGRESS.md) — live status and session log
- [Decisions](docs/decisions/) — architecture decision records
