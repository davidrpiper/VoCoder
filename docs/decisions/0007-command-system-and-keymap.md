# 0007 — Command system, keymap and keyboard overlays

- Status: Accepted
- Date: 2026-10-17
- WP: P1-05

## Context

DESIGN §2.1 says keys, the palette, the leader popup, voice and the brain all dispatch through
one command registry. P1-04 left a minimal `Command` (id, title, category, `perform`) and P1-03 a
temporary key → `UIAction` map in `UIHost` (ADR 0005). P1-05 has to fill in the rest
(bindings, phrases, parameters, risk tier, availability, spoken result, undo hook), replace the
temporary map, and add the leader/which-key, the palette and help. Some forces:

- Core can't import the UI, but navigation commands (`list.down`) act on the UI's focus path,
  and Core commands need to know what is focused (the voice cursor is the focus, §2.2).
- The palette is a modal with a text field: typed keys go to the bridge widget, and
  availability has to be judged against what was focused *before* it opened.
- After the leader, the next key must reach the keymap even when a text field has focus.
- Key presses must take effect in order. A plain `Task` per key would let the next key run
  before the previous command, and tests couldn't assert synchronously.
- Config overrides for keys are P1-06's (TOML), but their shape belongs to the keymap.

## Decision

- **`Command` (Core)** gains `keys: [KeyBinding]`, `voicePhrases`, `params:
  [CommandParameter]` (text, integer with a range, or choices computed from the context),
  `risk: RiskTier` (`readOnly`/`reversible`/`outward`) and `isAvailable(CommandContext)`.
  `perform` stays `(CommandContext) async throws -> Void`. A command reports its outcome
  through the context (`say(_:)` for the spoken result, `offerUndo(_:)`). Two overloads with
  different closure return types turned out to be ambiguous for multi-statement closures.
- **`CommandContext`** carries `state`, a `FocusSnapshot` (focused id and scope path as plain
  strings), validated `arguments` and the `source` (key/palette/voice/brain/program).
- **`CommandDispatcher` (Core)** owns the registry and is the only way commands run:
  1. It checks availability, then that each required argument is present and valid
     (parameters validate and convert values).
  2. Before an `outward` command it asks the `CommandConfirmer`. Without one, outward commands
     run only from key, palette or program sources and are declined from voice or the brain.
  3. It runs the command, logs the id, source and argument *names* (never values), and keeps an
     MRU list.
  4. It hands `UndoAction`s to an `UndoSink`.

  The UI supplies the focus through `focusProvider`. `AppCore` creates the dispatcher with
  Core's built-in tab commands first, then the modules' commands. `AppCore.run` forwards to the
  dispatcher.
- **Keys (Core)**:
  - `KeyChord` canonicalises both bridge names (`Ctrl-Space`) and config style
    (`ctrl+space`) to the bridge's names.
  - `KeySequence` has a `<leader>` placeholder. `KeyBinding` adds optional fixed arguments
    (`<leader> 3` → `tab.goto tab=3`).
  - `Keymap` is built from the registry plus `KeyBindingOverrides` (leader chord; per command,
    replace or unbind, with `parse` for config strings).
  - A sequence that is a prefix of a longer one is dropped with an issue, since there are no
    timeouts. Unknown ids and invalid sequences become issues too.
  - Several commands may share a sequence. The first *available* one runs, so a binding can
    depend on the context.
  - `KeyResolver` is the state machine: pending, matched, cancelled (Esc or a dead end; the key
    is swallowed), or unbound (the key falls through).
- **Fuzzy ranking (Core)**: our own scorer (ADR 0004), a subsequence DP with bonuses for word
  starts, camelCase, prefixes and runs. `CommandSearch` weights title over id, voice phrases and
  category. Ties go to the most recent command, then registration order.
- **UI**:
  - `NavigationCommands` (`list.*`, `ui.activate/cancel/left/right`, `focus.next/previous`,
    `palette.open`, `help.toggle`, `app.quit`) send `UIAction`s through `UIHost.perform(_:)`.
  - `KeyboardController` registers them as built-ins, ahead of everything else
    (`CommandRegistry.prepend`; a module command with the same id is removed and reported). It
    builds the keymap and takes over `UIHost.onKey`, which replaces `keyMap`/`onUnhandledKey`.
  - Matched commands run with **`Task.immediate`**: synchronously up to the first suspension.
  - While a sequence is pending, `UIHost.suspendsWidgetFocus` holds keys back from the focused
    widget.
  - Invoking a command with missing parameters opens the palette at a parameter prompt (choice
    list or text field). This applies from keys too.
  - While the palette or help is open, the dispatcher sees the focus from before it opened.
    Commands chosen in the palette run after it closes and focus is restored.
  - The overlays (which-key at the bottom, palette, help) are views in `CommandOverlays`,
    composed with `.commandOverlays(keyboard)`. They're `trap` focus scopes drawn with the
    bridge's new `clearUnder` modifier (FTXUI `clear_under`).
- **Tab navigation moved from P1-07 into P1-05**: `tab.next`/`tab.previous` (`<leader> t n/p`)
  and `tab.goto` (`<leader> 1…9`, `Alt-1…9`, a choice parameter). Close, reorder and go-to by
  alias stay in P1-07.
- The demo and the gallery override `app.quit` to add `q` (a `KeyBindingOverrides` example).
  The gallery's dev keys are now gallery commands.

## Consequences

- Every user-facing key now goes through a command. No ad-hoc key handlers remain in the demo,
  the gallery or the UI layer. `KeyMap.defaultBindings` is gone.
- Voice (P2-05) gets phrases, parameters and risk tiers from the registry, and dispatches with
  `source: .voice`. The dispatcher declines outward commands until P2-07 sets a confirmer.
- P1-06 maps config `[keys]` onto `KeyBindingOverrides.parse` and calls
  `KeyboardController.rebuildKeymap(overrides:)`. Keymap issues should join `vocoder doctor`.
- P1-07 supplies a `CommandConfirmer` dialog, shows `KeyboardController.lastFailure` as a toast,
  builds the hint bar from `keyHint(for:)`, and composes `.commandOverlays` in the chrome.
- FTXUI merges box-drawing characters where an overlay's border touches a border below
  (`┴`). This is cosmetic and accepted.
- DESIGN §2/§3.3/§4.2/§4.10/§6 and PLAN P1-06/P1-07/P2-05/P2-07 notes updated.

## Alternatives considered

- **Commands return a `CommandOutcome`** (with a `Void` convenience overload). Swift found
  multi-statement closures ambiguous. A single return type would force `return .done`
  everywhere.
- **`UIAction` in Core with an abstract "UI performer" in the context.** That leaks UI concepts
  into Core for one use. UI-level commands living in the UI target is simpler.
- **Leader timeouts** (Vim-style `g` vs `g g`). Timeouts make keys racy and hard to test. A
  shadowing binding is reported instead.
- **The palette as a separate list widget with its own focus.** Tab would move focus between
  the field and the list. Keeping focus in the field and moving the selection with arrow
  commands is simpler, and the same commands work for voice.
- **One `Task` per key press.** It reorders effects relative to later keys, and it needs async
  tests for every key.
