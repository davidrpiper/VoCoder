# 0005 — View DSL, focus tree and key routing

- Status: Accepted
- Date: 2026-10-17
- WP: P1-03

## Context

P1-03 builds `VoCoderUI` on the bridge's node tree (ADR 0001). How views are written, who owns
focus and how keys reach a focused list decide how P1-05's commands attach to the UI, and how
"next" / "open" by voice can act on the focused item (DESIGN §2.2: the voice cursor *is* the
keyboard focus). CLAUDE.md also requires that every user-facing action is a registered command,
with no ad-hoc key handlers. P1-05 (commands, keymap) doesn't exist yet, but focus traversal and
list navigation need to be testable end to end now.

## Decision

- **Views** are value types conforming to a `@MainActor` `View` protocol with a `@ViewBuilder`
  `body`, SwiftUI-like but without view-local state: state lives in `@Observable` view models.
  Built-in views lower to `VCNode`s (internal protocol), so modules import only `VoCoderUI`.
  `UIHost` renders the root inside `withObservationTracking` and re-renders (coalesced) when
  anything the render read changes.
- **Theme**: views use semantic roles (`.accent`, `.selection`, …); `Theme` maps roles to RGB
  values (dark and light built-ins, `auto` follows the macOS appearance until config overrides
  it in P1-06). Built-in colours are picked to stay distinct after degrading to 256 colours
  (tested). The bridge gained a coloured border that doesn't colour the content, and a
  process-wide colour-depth setting plus a depth-specific ANSI off-screen render.
- **Focus**: each render collects a focus tree of leaves (`Focusable`, `TextField`, `ListView`,
  focusable `ScrollView`) and scopes (`.focusScope(id, trap:)`) keyed by stable `FocusID`s.
  `FocusManager` owns the focused leaf; after each render it keeps it, or moves to the nearest
  survivor in the old order within the innermost surviving scope. Scopes remember their last
  leaf. A `trap` scope (modal) confines focus while rendered; focus returns to the previous leaf
  when it closes. Focusing an id that isn't rendered yet is deferred until it appears. The
  bridge's focused widget is synced as soon as focus changes, so keys typed right after Tab
  reach the right field.
- **Key routing is a responder chain of generic actions**: a key maps to a `UIAction`
  (`moveUp/Down`, `pageUp/Down`, `moveToFirst/Last`, `activate`, `cancel`, `focusNext/Previous`).
  Focus actions go to the focus manager; the rest go to action handlers along the focus path,
  innermost first. Keys with no action, or that nothing handled, go to `onUnhandledKey`.
- **The key → action map is temporary** (`KeyMap.defaultBindings`: j/k/arrows, PgUp/PgDn,
  Ctrl-u/d, g/G/Home/End, Enter, Esc, Tab/Shift-Tab). P1-05 replaces it with registered
  commands (`list.next`, `focus.next`, …) that have key bindings, voice phrases and risk tiers,
  and dispatch the same `UIAction`s through `UIHost.perform(_:)`. `onUnhandledKey` becomes the
  keymap's entry point.

## Consequences

- P1-05 doesn't touch views: it binds keys and phrases to commands that call
  `perform(.moveDown)` etc. Voice "next" works on any list without per-view code.
- Lists and tables are Swift-drawn rows in a bridge scroll frame (selection kept visible with a
  focus marker), not the bridge's `menu` widget, so rows can be rich. The viewport height isn't
  known in Swift, so page size is a `ListState`/`ScrollState` setting (default 10).
- `TableView` columns are fixed width or flexible; rows stay aligned with at most one flexible
  column.
- Snapshot tests live in `VoCoderUITestSupport` (separate so Core tests don't link FTXUI) with
  goldens next to each test file in `__Snapshots__/<TestFile>/`.
- DESIGN §4.1 (new target), §4.2 (DSL, focus, colours) and §6 updated; PLAN P1-03 split
  (markdown renderer → P1-03b), P1-05 and P1-07 notes.

## Alternatives considered

- **No key bindings until P1-05** (views expose only methods): keeps the rule literally, but
  the key → focus → list path couldn't be tested end to end until P1-05.
- **Per-view key handlers** (`.onKey("j")`): exactly the ad-hoc handlers CLAUDE.md forbids, and
  voice would need a parallel path.
- **Bridge `menu` widget for lists**: plain strings only; no rich rows or theme colours.
- **Focus owned by the bridge (FTXUI components)**: FTXUI's focus is per component tree and
  doesn't know scopes, traps or the voice cursor; Swift owning focus keeps it testable and
  shared with voice.
