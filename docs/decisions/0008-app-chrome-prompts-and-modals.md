# 0008 — App chrome, command prompts and modals

- Status: Accepted
- Date: 2026-10-17
- WP: P1-07

## Context

P1-07 builds the app's persistent frame (DESIGN §3.1): tab bar, voice and hint bars, modals,
toasts, the Home tab and the remaining tab commands. It replaces P1-04's `DevShell` and
`DemoApp`. Several of these pieces cross the Core/UI boundary or the bridge:

- Commands live in Core and in modules. Some need to ask the user something while they run
  (a confirm, a name, a choice from a list). Core can't import the UI, and voice will answer
  the same questions in Phase 2.
- `CommandDispatcher` already asks a `CommandConfirmer` before outward commands (ADR 0007), but
  nothing implemented it.
- The tab bar has to handle more tabs than fit. Only FTXUI's layout knows the width; a view
  is built before layout.
- Home is a built-in tab, but `TabFactory`s come from modules, and Core can't create a
  `ViewTab`.
- P1-10's repo tab must pop out to `claude --resume` and `$EDITOR`. The run loop, signal
  handling and spawn helper were in the executable, where modules can't reach them.
- The voice bar needs a state to draw before the voice layer exists.

## Decision

- **`CommandPrompter` (Core)**: `confirm(ConfirmRequest) -> Bool`, `askText(TextRequest) ->
  String?`, `choose(ChoiceRequest) -> String?` (the choice's value), `notify(Notice)` (no wait)
  and `cancelAll()`. Every request resolves exactly once. Cancelled requests are false/nil, and
  stacked requests are answered newest first. Commands reach it as `CommandContext.prompter`.
  The dispatcher hands over its `prompter`, or `DecliningPrompter` (declines everything) when
  none is set. `FakePrompter` (scripted or manual answers) is in `VoCoderFakes`, and
  `CommandPrompterContract` is in `VoCoderTestSupport`. The chrome's presenter and the fake both
  run the contract.
- **`ModalPresenter` (UI)** implements both `CommandPrompter` and `CommandConfirmer`. It keeps a
  stack of modals (confirm dialog, text prompt, fuzzy-filtered list picker), each a centred box
  in a `trap` focus scope. It resumes their continuations and cancels them all when the app
  stops.
  - **Keys:** the existing navigation commands drive the modals: Enter (`ui.activate`), Esc
    (`ui.cancel`), arrows, Tab. `modal.confirm` / `modal.deny` (`y` / `n`) are available only
    while a confirm dialog has focus. There are no ad-hoc key handlers.
  - **Outward commands** are confirmed with a dialog that **starts on Cancel**
    (`ConfirmRequest.confirmIsDefault = false`), so a reflexive Enter sends nothing (user
    decision at plan time). The dialog lists the command's arguments and its confirm button is
    named after the command.
  - **Declined confirmations** aren't failures: the keyboard controller doesn't report them.
- **Toasts**: `ToastCenter` (at most three; info/success/error; errors stay 6 s, others 4 s; its
  `sleep` can be replaced for tests). They show command failures (through the new
  `KeyboardController.onFailure`, with command titles instead of ids), `notify` calls and module
  problems at startup.
- **Tab bar overflow is a bridge node**: `VCNode strip(_:keepingVisible:)` lays its children out
  left to right. When they don't fit, it shows the kept child and as many neighbours as fit
  (preferring those after it), with dim `‹n` / `n›` markers counting the hidden ones. When even
  the kept child doesn't fit with markers, it shows that child alone. The hint bar uses the same
  node, so whole hints drop off instead of FTXUI squashing every text.
- **`Tab` gains `isClosable`** (default true) and **`hintCommands`** (the selected tab's entries
  in the hint bar, shown when available). Tabs that can't be closed also stay in place: the
  move commands don't move them or move anything past them.
- **Tab commands**: `tab.switch` (`<leader> t t`, choices titled with aliases), `tab.close`
  (`<leader> t c`), `tab.moveLeft` / `tab.moveRight` (`<leader> t h` / `l`). `AppState` gains
  `move(_:to:)` and `tab(matching:)`. The latter matches a title or alias, ignoring case and a
  leading "the", and returns nil when ambiguous; it is for voice. Closed tabs don't come back
  until restart; session restore (P1-11) brings them back (user decision).
- **Home** is `HomeTab` in `VoCoderUI`, passed to `AppCore` as a **built-in tab factory**
  (`AppCore(…, builtInTabs:)`; built-ins open first within their placement and are attributed
  to `core`). It shows the attention items (most urgent first), module problems and a short
  orientation note.
- **`AppState.voice: VoiceStatus`** (mic off/idle/listening/thinking/speaking, transcript,
  speaking text). It stays `.off` until Phase 2 drives it.
- **`AppShell`** (UI) wires `AppCore`, the Home tab, `KeyboardController`, `ModalPresenter`
  (as prompter and confirmer) and `ToastCenter`. **`AppChrome`** draws them: tab bar, divider,
  tab content, divider, voice bar, hint bar, then toasts, modals and the keyboard overlays.
  DESIGN's outer border is dropped (it costs two columns and two rows at 80×24). The executable
  and the tests set the shell up the same way.
- **`TerminalSession`** (UI, moved from the executable): it runs the loop with the ADR 0001
  signal model, and `popOut(_:arguments:directory:environment:banner:) async -> Int32` hands the
  terminal to an interactive program (`posix_spawnp` in our process group, signal defaults
  restored, SIGINT ignored meanwhile).
- `vocoder` with no arguments now runs the TUI over the real modules (with no config yet, only
  Home has content), and `--demo` does the same over `DemoModule`. The development `q` key is
  gone from the app (quit is `<leader> q` or Ctrl-C); the gallery keeps it.

## Consequences

- Commands in any module can ask questions and show notices without touching the UI. P2-07
  answers the same requests by voice (spoken read-back, "confirm"), either by composing with
  `ModalPresenter` or by replacing the dispatcher's prompter/confirmer.
- A confirm dialog now guards outward commands from every source, voice included. Voice no
  longer gets the "decline without a confirmer" default.
- P1-10 pops out through `TerminalSession.popOut`. How a module reaches the session (a service
  or a registry) is decided there.
- P1-06 swaps `InMemorySecretStore` for the Keychain store and passes config and repos to the
  real app.
- `make pty-test` also smoke-tests the app (`vocoder --demo` and `vocoder`).
- DESIGN §3.1, §3.3, §4.1, §4.2, §4.10 and PLAN P1-06/P1-07/P1-10/P1-11/P2-07 are updated.

## Alternatives considered

- **Commands return "needs input" and the UI re-runs them with arguments** (palette-style
  parameter prompts only). This covers inputs known in advance but not questions asked mid-run
  (confirm after inspecting state, pick from data fetched by the command).
- **Prompts as an extension point in the module registry.** That would allow several
  implementations, but only one answers at a time (the chrome, or voice), so a single
  dispatcher-held protocol is enough.
- **Tab bar overflow computed in Swift from `UIHost.size`.** The size isn't known in off-screen
  renders, and a view would depend on the terminal rather than its box. The C++ node knows
  its real box.
- **Confirm dialog starting on Confirm.** It's quicker, but Enter by reflex would send an
  outward action; `y` is one key anyway.
- **A reopen-closed-tab command.** A closed tab has released its resources (`willClose`), so
  reopening means recreating it from its factory. Session restore in P1-11 covers this
  properly.
