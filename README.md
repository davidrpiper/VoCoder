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
| `make run` | Runs `vocoder` (`ARGS=bridge-demo` shows the UI bridge demo) |
| `make snapshot-update` | Regenerates UI snapshot goldens (review the diff) |
| `make fmt` / `make lint` | Toolchain `swift format` (lint is `--strict`) |
| `make logs` | Tails `~/Library/Logs/VoCoder/vocoder.log` |
| `make clean` | Removes build products |

## Docs

- [Design](docs/DESIGN.md) — architecture and UX
- [Plan](docs/PLAN.md) — work packages and milestones
- [Progress](docs/PROGRESS.md) — live status and session log
- [Decisions](docs/decisions/) — architecture decision records
