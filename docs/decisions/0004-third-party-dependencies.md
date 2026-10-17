# 0004 — Third-party dependencies for Phase 1

- Status: Accepted
- Date: 2026-10-17
- WP: P0-06

## Context

PLAN.md's dependency table left CLI parsing, TOML, formatting, logging and snapshot testing open
until the spikes were done. Constraints: no Swift target may enable C++ interop (DESIGN §4.2), the
dependency graph should stay small and auditable, and the Swift 6.4 toolchain already ships
Swift Testing and `swift format` (verified on this machine).

Candidates checked (2026-10-17):
- **swift-argument-parser** (Apple), latest 1.8.2, pure Swift.
- **TOMLDecoder** (dduan), latest 0.4.5, pure Swift, `Codable` decoding, no runtime dependencies
  (benchmark/docs/formatting packages are opt-in via env vars), runs the TOML 1.0 compliance
  suite, maintained (last push 2026-07). Decode only.
- **TOMLKit** (LebJe), wraps toml++ (C++).
- Official Swift MCP SDK: already rejected in ADR 0002.

## Decision

| Need | Choice |
|---|---|
| CLI parsing | swift-argument-parser, `from: "1.8.2"` |
| TOML | TOMLDecoder, `from: "0.4.5"` (decode only; `vocoder config init` writes a template string) |
| Formatting / lint | toolchain `swift format` (`make fmt`, `make lint` = `swift format lint --strict`); no SwiftLint |
| Logging | `os.Logger` + a small hand-written rotating file sink; no swift-log |
| Snapshot testing | hand-written helper over the bridge's off-screen render; no third-party library |
| Unit tests | Swift Testing (toolchain) |
| GraphQL (Linear, P4) | hand-written queries over URLSession; no codegen |
| MCP | none (ADR 0002) |
| TUI | FTXUI, vendored submodule (ADR 0001) |

`Package.resolved` is committed. Adding any further third-party dependency requires an ADR.

## Consequences

- Two SwiftPM dependencies in total, both pure Swift; builds stay offline-capable after the first
  resolve.
- TOML errors: TOMLDecoder reports syntax errors and `DecodingError` coding paths; P1-06 wraps
  these into readable messages (file, key path, expected type) itself.
- If TOMLDecoder ever stalls, a hand-written parser for our subset of TOML is the fallback; the
  config layer must keep TOMLDecoder behind a small internal function so it can be swapped.
- PLAN.md dependency table updated; P1-01 adds both packages.

## Alternatives considered

- **TOMLKit:** C++ underneath (toml++); unnecessary C++ in the dependency graph.
- **Hand-written TOML parser:** more code and edge cases than it saves.
- **swift-log / swift-snapshot-testing / SwiftLint:** extra dependencies for things the OS,
  toolchain or a few dozen lines already cover.
