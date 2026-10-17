// The built-in UI commands (ADR 0007): list and focus navigation send `UIAction`s along the
// focus path, so they work on any list, panel or dialog; plus the palette, help and quit.
import VoCoderCore

public enum NavigationCommands {
  public static let category = "Navigation"
  public static let up: CommandID = "list.up"
  public static let down: CommandID = "list.down"
  public static let pageUp: CommandID = "list.pageUp"
  public static let pageDown: CommandID = "list.pageDown"
  public static let first: CommandID = "list.first"
  public static let last: CommandID = "list.last"
  public static let left: CommandID = "ui.left"
  public static let right: CommandID = "ui.right"
  public static let activate: CommandID = "ui.activate"
  public static let cancel: CommandID = "ui.cancel"
  public static let focusNext: CommandID = "focus.next"
  public static let focusPrevious: CommandID = "focus.previous"
  public static let palette: CommandID = "palette.open"
  public static let help: CommandID = "help.toggle"
  public static let quit: CommandID = "app.quit"

  /// The commands for `keyboard`'s host; `quit` stops the app.
  @MainActor
  static func make(
    for keyboard: KeyboardController, quit stop: @escaping @MainActor @Sendable () -> Void
  )
    -> [Command]
  {
    func action(
      _ id: CommandID, _ title: String, _ action: UIAction, keys: [KeyBinding],
      phrases: [String] = []
    ) -> Command {
      Command(id: id, title: title, category: category, keys: keys, voicePhrases: phrases) {
        [weak keyboard] _ in
        _ = keyboard?.host.perform(action)
      }
    }
    return [
      action(up, "Move up", .moveUp, keys: ["k", "ArrowUp"], phrases: ["up", "previous"]),
      action(down, "Move down", .moveDown, keys: ["j", "ArrowDown"], phrases: ["down", "next"]),
      action(pageUp, "Page up", .pageUp, keys: ["PageUp", "Ctrl-u"], phrases: ["page up"]),
      action(
        pageDown, "Page down", .pageDown, keys: ["PageDown", "Ctrl-d"], phrases: ["page down"]),
      action(first, "Go to first", .moveToFirst, keys: ["g", "Home"], phrases: ["top"]),
      action(last, "Go to last", .moveToLast, keys: ["G", "End"], phrases: ["bottom"]),
      action(left, "Move left", .moveLeft, keys: ["ArrowLeft"]),
      action(right, "Move right", .moveRight, keys: ["ArrowRight"]),
      action(activate, "Open", .activate, keys: ["Enter"], phrases: ["open", "select"]),
      action(cancel, "Back", .cancel, keys: ["Esc"], phrases: ["back", "cancel"]),
      action(focusNext, "Focus next", .focusNext, keys: ["Tab"]),
      action(focusPrevious, "Focus previous", .focusPrevious, keys: ["Shift-Tab"]),
      Command(
        id: palette, title: "Command palette", category: "App", keys: ["Ctrl-p", "<leader> p"],
        voicePhrases: ["command palette"]
      ) { [weak keyboard] _ in
        keyboard?.openPalette()
      },
      Command(
        id: help, title: "Help", category: "App", keys: ["?", "<leader> ?"],
        voicePhrases: ["help"]
      ) { [weak keyboard] _ in
        keyboard?.toggleHelp()
      },
      Command(id: quit, title: "Quit", category: "App", keys: ["<leader> q", "Ctrl-c"]) { _ in
        stop()
      },
    ]
  }
}
