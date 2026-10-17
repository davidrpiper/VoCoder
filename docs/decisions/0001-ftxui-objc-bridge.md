# 0001 — FTXUI via SwiftPM + ObjC++ bridge: validated, with key/signal rules

- Status: Accepted
- Date: 2026-10-17
- WP: P0-01

## Context

DESIGN §4.1–4.3 proposed compiling FTXUI as a SwiftPM C++ target and driving it from Swift through
an ObjC++ render protocol (open risk #6). The spike (`spikes/ftxui-bridge/`, see its FINDINGS.md)
built this against FTXUI v7.0.3 and tested it in Terminal.app and Ghostty (user-verified) and in a
scripted pty.

Evidence: clean build 5.7 s, zero warnings, no `unsafeFlags`; Swift 6 strict concurrency with no
C++ interop; 80k cross-thread `setRoot` calls coalesced into ~90 frames, ~20 ms average redraw
latency, ~0.2 % CPU; terminal restored on `q`, Ctrl-C, SIGINT, SIGTERM, SIGHUP; stable off-screen
render. It also surfaced three behaviours that the design didn't anticipate:

1. Ctrl-Space sends NUL, which FTXUI also uses for `Event::Custom` and for its own SIGWINCH
   notification.
2. On SIGINT/SIGTERM/SIGHUP (and Ctrl-C by default) FTXUI restores the terminal, then re-raises
   the signal, killing the process before app shutdown code runs.
3. Alt-digit keys need Option-as-Meta/Alt, off by default in both terminals; Ghostty sends CSI-u
   (`ESC[105;5u`) for Ctrl-I, which FTXUI doesn't parse.

## Decision

- **Go** with the FTXUI + ObjC++ bridge approach as designed. Pin FTXUI ≥ 7.0.2 (thread-safe
  `PostEvent`); currently v7.0.3 at `Vendor/FTXUI`. SwiftPM target: sources
  `src/ftxui/{screen,dom,component,util}`, `include/` public, `src/` header path, C++20, excluding
  tests/fuzzers/meson files and the stale `component/loop.cpp`.
- The bridge redraws with a **private special event**, never `Event::Custom`, and classifies a
  NUL event as a resize only when the terminal size changed; otherwise it is Ctrl-Space.
- **Ctrl-C is a key** (`ForceHandleCtrlC(false)`) handled by the command system. The app sets
  SIGINT/SIGTERM/SIGHUP to `SIG_IGN` and observes them via `DispatchSource`, so FTXUI's terminal
  restore still runs and its re-raise is harmless; shutdown is graceful. Ctrl-\ stays a hard exit.
- The bridge decodes **CSI-u** key sequences into normalised key names.
- `Ctrl-Space 1…9` is the guaranteed tab-jump binding; `Alt-1…9` remains as a convenience that
  requires Option-as-Meta/Alt, which first-run / `vocoder doctor` explains.

## Consequences

- DESIGN §3.3 (tab keys), §4.2 (events, Ctrl-Space, signals), §4.3 (App loop model, coalescing),
  §5 (terminal table), §8 (risk 6 resolved) updated. PLAN P1-02 scope and notes updated.
- The NUL heuristic can, in theory, lose a Ctrl-Space pressed in the same frame as a resize. An
  upstream FTXUI change giving SIGWINCH its own event would remove it; worth proposing.
- FTXUI bumps must re-check its CMake source list against what SwiftPM compiles.
- Ghostty already distinguishes Ctrl-I from Tab without the kitty protocol, which eases P6-02.

## Alternatives considered

- **Swift C++ interop directly:** rejected in DESIGN §4.2 (viral flag, `std::function`/virtual
  subclassing); the spike gave no reason to revisit.
- **CMake-built static library:** unnecessary — SwiftPM builds FTXUI cleanly.
- **Patching FTXUI for Ctrl-Space/SIGWINCH:** avoided for now (vendored code stays pristine);
  the bridge-side heuristic is sufficient.
- **Letting FTXUI kill the process on signals:** terminal is restored, but agent sessions and
  state couldn't shut down cleanly.
