# P0-01 — FTXUI + ObjC++ bridge build spike: findings

- Date: 2026-10-17 · Toolchain: Xcode 27.1, Swift 6.4, macOS 26 SDK 27.0, Apple M5 Max (18 cores)
- FTXUI: v7.0.3 (git submodule `Vendor/FTXUI`, symlinked into this package)
- Run: `swift run -c release ftxui-spike` · off-screen: `swift run ftxui-spike --snapshot` ·
  stress: `--stress`. Diagnostics go to `ftxui-spike-<TERM_PROGRAM>.log` in the cwd.

## Verdict: **GO**

FTXUI builds as a plain SwiftPM C++20 target, an ObjC++ bridge with plain-ObjC headers drives
it from Swift 6 (strict concurrency, no C++ interop, no warnings), and it behaves correctly in
Terminal.app and Ghostty. Three things the real bridge must handle (Ctrl-Space vs FTXUI's
internal events, signals/Ctrl-C, CSI-u keys) are solved in the spike and listed below.

## What was built

- `CFTXUI`: SwiftPM target over `Vendor/FTXUI` — sources `src/ftxui/{screen,dom,component,util}`,
  `publicHeadersPath: "include"`, `headerSearchPath("src")`, `cxxLanguageStandard: .cxx20`.
- `VCBridge` (ObjC++ `.mm`, plain-ObjC header): immutable `VCNode` tree (vbox/hbox/text/
  separator/filler/border/input + bold/dim/inverted/flex/colour), `VCEvent`, `VCRenderer`
  (`setRoot:`, focus, widget get/set, `start`/`stop`, off-screen `renderToString`).
- `ftxui-spike` (Swift 6): three tabs, a stateful input, a clock ticking from a detached task
  calling `setRoot` off the main thread, a key log tab, signal handling.

## Measurements

| What | Result |
|---|---|
| Clean build, debug (whole spike incl. FTXUI) | 5.7 s wall |
| Clean build, release | 4.9 s wall |
| Incremental: touch bridge `.mm` / touch `main.swift` | 3.8 s / 0.8 s |
| Release binary size | 0.6 MB |
| Warnings | 0 (FTXUI included) |
| `unsafeFlags` needed | **No** |
| setRoot → frame latency (pty) | avg ~20 ms; max 400–500 ms only during startup (see below) |
| Coalescing: 80,000 `setRoot` from 4 threads in ~7 s | ~90 frames drawn, no crash/race |
| CPU, 10 redraws/s | ~0.2 % |

## Acceptance

| Criterion | Result |
|---|---|
| Runs correctly in Terminal.app | ✅ (user-verified: tabs, input incl. é/日本, resize, quit) |
| Runs correctly in Ghostty | ✅ (user-verified, same checks) |
| Resize works | ✅ (both terminals + pty-driven SIGWINCH) |
| Terminal restored on exit (`q`) and Ctrl-C | ✅ user-verified; pty-verified for `q`, Ctrl-C, SIGINT, SIGTERM, SIGHUP: exit 0, alt screen left, cursor shown, tty modes identical (only the kernel's transient `PENDIN` bit differs) |
| Off-screen render produces stable text | ✅ two renders identical for every tab; plain-text and ANSI variants |
| Clean build time recorded | ✅ above |

## Findings and gotchas

1. **FTXUI 7 renamed `ScreenInteractive` → `App`** (alias kept). DESIGN refers to
   `ScreenInteractive::Loop`/`WithRestoredIO`; same API on `App`.
2. **Stale `src/ftxui/component/loop.cpp`** duplicates `Loop` symbols that now live in `app.cpp`
   and isn't in FTXUI's CMake list → duplicate-symbol link error. Exclude it. Also exclude
   `*_test.cpp`, `*_fuzzer.cpp`, `meson.build`. SwiftPM excludes don't glob, so `Package.swift`
   enumerates them with `FileManager` (works fine). When bumping FTXUI, diff its CMake source
   list against what SwiftPM compiles.
3. **SwiftPM in Swift 6.4 uses the Swift Build backend** (`.build/out/…`). Package-root-escaping
   paths aren't allowed; a symlink to `Vendor/FTXUI` works (moot for P1-01: package at repo root).
4. **`MacTypes.h` declares `bold` (and other short names) globally** — in `.mm` files never
   `using namespace ftxui;`; qualify (`ftxui::bold`).
5. **Ctrl-Space ≡ `Event::Custom`.** Ctrl-Space sends NUL; FTXUI's `Event::Custom` is
   `Special({0})`, and FTXUI itself posts `Special({0})` on SIGWINCH and selection change. So:
   - never use `Event::Custom` for bridge redraws — use a private special event
     (`Special("\x1b[vocoder-redraw]")`);
   - a NUL event is a resize if `Terminal::Size()` differs from the last drawn size, otherwise
     Ctrl-Space. (Theoretical loss: Ctrl-Space pressed in the same frame as a resize.) A small
     upstream patch giving SIGWINCH its own event would remove the heuristic — worth proposing.
6. **Threading:** `App::PostEvent`/`Post`/`Exit` go through a mutex-protected task queue and are
   thread-safe (fixed in 7.0.2 — do not go below 7.0.2). The v7 loop is **not** blocking: it
   polls stdin and sleeps to a 60 fps cadence, so redraw latency is ≤ ~17 ms + render, CPU stays
   negligible, and an explicit 30 fps cap is unnecessary — the "pending redraw" flag is enough to
   coalesce. Bridge state is shared under one `std::recursive_mutex` (recursive because
   `Input::Render → Focused() → ActiveChild()` re-enters the bridge).
7. **Startup stalls of 400–500 ms** in the pty are FTXUI waiting for terminal capability
   replies (XTVERSION/DA, 500 ms timeout). Real terminals answer quickly; not observed by the user.
   Keep in mind for snapshot/pty tests (use off-screen render, not the loop).
8. **Signals and Ctrl-C.** By default FTXUI turns Ctrl-C into SIGINT and, on SIGINT/SIGTERM/
   SIGHUP, restores the terminal, exits the loop and **re-raises the signal with the previous
   handler**, killing the process before any Swift shutdown code runs (exit 130). Solution used:
   - `ForceHandleCtrlC(false)` and the root component handles every key → Ctrl-C is just a key
     (`Ctrl-c`) for the command system (e.g. interrupt agent / quit).
   - Swift sets `SIG_IGN` for SIGINT/SIGTERM/SIGHUP and observes them with `DispatchSource`
     (kqueue sees ignored signals). FTXUI's re-raise is then harmless, the loop thread returns,
     `onExit` runs, the app shuts down gracefully (exit 0). Ctrl-\ (SIGQUIT) remains a hard
     escape hatch; Ctrl-Z suspend is FTXUI's default.
9. **Stateful widgets keyed by id work.** The `Input` component lives in a C++ map keyed by
   widget id, survives tree swaps, is attached as a child of the root component so `Focused()`
   resolves (cursor), and reports changes as `widgetChanged` events. Swift owns focus
   (`setFocusedWidget:`); Esc/Tab/Ctrl-C bypass the focused input.
10. **Keyboard reality (user-verified):**

    | Key | Terminal.app (Option as Meta **on**) | Ghostty (defaults) |
    |---|---|---|
    | Ctrl-Space | `00` ✅ | `00` ✅ |
    | Alt-1 | `1b 31` ✅ | `¡` (`c2 a1`) — Option composes; needs `macos-option-as-alt = true` |
    | Ctrl-I | `09` = Tab (indistinguishable) | `1b [105;5u` (CSI u) — distinct from Tab |

    FTXUI doesn't parse CSI-u; the bridge now decodes `ESC [ code ; mods u` (`Ctrl-i`, `Ctrl-m`,
    `Ctrl-Alt-Space`, … — pty-tested with Ghostty's bytes). Implications for DESIGN §3.3:
    **Alt-1…9 only work with Option-as-Meta/Alt configured**, which neither terminal does by
    default (Terminal.app: Profiles → Keyboard → "Use Option as Meta key"). Keep Alt-digits as a
    convenience, make the leader route (`Ctrl-Space 1…9`) the always-available binding, and have
    first-run/`vocoder doctor` explain the setting.
11. **Unicode:** é, CJK (double width) and box drawing render and edit correctly. FTXUI counts
    emoji + VS16 (`🎙️`) as width 1 while terminals may draw 2 — no misalignment was reported in
    the user test, but prefer text glyphs/emoji without VS16 in chrome.
12. **Off-screen plain text** must mirror `Screen::ToString`: empty cells → space, skip the cell
    after a full-width glyph. `ToString()` itself emits styles (ANSI); snapshot tests should store
    plain text plus optionally the ANSI form.
13. FTXUI appends a NUL byte to every output flush (an Emscripten flush hack). Terminals ignore
    it; worth knowing when diffing captured output.
14. No `Package.swift` C++ settings leak into Swift: the `ftxui-spike` target compiles with no
    interop flags while depending (transitively) on the C++ target.

## Recommended changes

- DESIGN §3.3: Alt-digit caveat; leader digits as the guaranteed tab route. (Done with ADR 0001.)
- DESIGN §4.2/§4.3: private redraw event, NUL disambiguation, Ctrl-C/signal model, v7 loop
  model, `App` naming. (Done with ADR 0001.)
- DESIGN §5: Option-as-Alt row; Ghostty CSI-u row. (Done.)
- P1-02 (UI bridge): carry over items 2, 4, 5, 6, 8, 9, 10 (CSI-u decoding), 12; pin FTXUI ≥ 7.0.2.
- P1-01: FTXUI target settings from this `Package.swift` (excludes enumerated, no unsafeFlags).
- P6-02 (kitty keyboard): Ghostty already sends CSI-u for ambiguous keys without negotiation;
  the decoder written here is the starting point.
