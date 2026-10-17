// Built-in tab navigation (DESIGN §3.3: `Ctrl-Space 1…9` always works, `Alt-1…9` where the
// terminal sends Option as Alt). Closing, reordering and going to a tab by alias arrive with the
// chrome (P1-07).

public enum TabCommands {
  public static let next: CommandID = "tab.next"
  public static let previous: CommandID = "tab.previous"
  public static let goto: CommandID = "tab.goto"

  @MainActor
  public static var all: [Command] {
    let hasTabs: Command.Availability = { !$0.state.tabs.isEmpty }
    return [
      Command(
        id: next, title: "Next tab", category: "Tabs", keys: ["<leader> t n"],
        voicePhrases: ["next tab"], isAvailable: hasTabs
      ) { context in
        step(context, by: 1)
      },
      Command(
        id: previous, title: "Previous tab", category: "Tabs", keys: ["<leader> t p"],
        voicePhrases: ["previous tab"], isAvailable: hasTabs
      ) { context in
        step(context, by: -1)
      },
      Command(
        id: goto, title: "Go to tab", category: "Tabs",
        keys: (1...9).flatMap { number -> [KeyBinding] in
          [
            KeyBinding(keys: "<leader> \(number)", arguments: ["tab": .text("\(number)")]),
            KeyBinding(keys: "Alt-\(number)", arguments: ["tab": .text("\(number)")]),
          ]
        },
        params: [CommandParameter("tab", title: "Tab", kind: .choice(tabChoices))],
        isAvailable: hasTabs
      ) { context in
        let tabs = context.state.tabs
        guard let number = context.arguments.integer("tab"), tabs.indices.contains(number - 1)
        else { return }
        let tab = tabs[number - 1]
        context.state.select(tab.id)
        context.say(tab.title)
      },
    ]
  }

  /// "1"…"n" (tab positions) titled "1 vocoder".
  @MainActor
  static func tabChoices(_ context: CommandContext) -> [CommandParameter.Choice] {
    context.state.tabs.enumerated().map { index, tab in
      CommandParameter.Choice(value: "\(index + 1)", title: "\(index + 1) \(tab.title)")
    }
  }

  @MainActor
  private static func step(_ context: CommandContext, by delta: Int) {
    let state = context.state
    let tabs = state.tabs
    guard !tabs.isEmpty else { return }
    let current = tabs.firstIndex { $0.id == state.selectedTabID } ?? 0
    let tab = tabs[(current + delta + tabs.count) % tabs.count]
    state.select(tab.id)
    context.say(tab.title)
  }
}
