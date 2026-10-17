// Built-in tab commands (DESIGN §3.3: `Ctrl-Space 1…9` always works, `Alt-1…9` where the
// terminal sends Option as Alt): next/previous/go to by number (P1-05), switch by name, close and
// reorder (P1-07). Tabs that can't be closed (Home) also stay where they are.

public enum TabCommands {
  public static let next: CommandID = "tab.next"
  public static let previous: CommandID = "tab.previous"
  public static let goto: CommandID = "tab.goto"
  public static let switchTo: CommandID = "tab.switch"
  public static let close: CommandID = "tab.close"
  public static let moveLeft: CommandID = "tab.moveLeft"
  public static let moveRight: CommandID = "tab.moveRight"

  @MainActor
  public static var all: [Command] {
    let hasTabs: Command.Availability = { !$0.state.tabs.isEmpty }
    let canClose: Command.Availability = { $0.state.selectedTab?.isClosable == true }
    let canMoveLeft: Command.Availability = { movableTarget($0.state, by: -1) != nil }
    let canMoveRight: Command.Availability = { movableTarget($0.state, by: 1) != nil }
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
      Command(
        id: switchTo, title: "Switch to tab", category: "Tabs", keys: ["<leader> t t"],
        params: [CommandParameter("tab", title: "Tab", kind: .choice(namedTabChoices))],
        isAvailable: hasTabs
      ) { context in
        guard let id = context.arguments.text("tab"), let tab = context.state.tab(TabID(id))
        else { return }
        context.state.select(tab.id)
        context.say(tab.title)
      },
      Command(
        id: close, title: "Close tab", category: "Tabs", keys: ["<leader> t c"],
        voicePhrases: ["close tab", "close this tab"],
        isAvailable: canClose
      ) { context in
        guard let tab = context.state.selectedTab, tab.isClosable else { return }
        context.state.close(tab.id)
        context.say("Closed \(tab.title)")
      },
      Command(
        id: moveLeft, title: "Move tab left", category: "Tabs", keys: ["<leader> t h"],
        isAvailable: canMoveLeft
      ) { context in
        move(context, by: -1)
      },
      Command(
        id: moveRight, title: "Move tab right", category: "Tabs", keys: ["<leader> t l"],
        isAvailable: canMoveRight
      ) { context in
        move(context, by: 1)
      },
    ]
  }

  /// Tab ids titled "api-server (the api, api)" (titles with aliases).
  @MainActor
  static func namedTabChoices(_ context: CommandContext) -> [CommandParameter.Choice] {
    context.state.tabs.map { tab in
      let aliases = tab.aliases.isEmpty ? "" : " (" + tab.aliases.joined(separator: ", ") + ")"
      return CommandParameter.Choice(value: tab.id.rawValue, title: tab.title + aliases)
    }
  }

  /// Where the selected tab would move by `delta`, if it may: both it and the tab it swaps with
  /// must be closable.
  @MainActor
  static func movableTarget(_ state: AppState, by delta: Int) -> Int? {
    guard let tab = state.selectedTab, tab.isClosable,
      let index = state.tabs.firstIndex(where: { $0.id == tab.id })
    else { return nil }
    let target = index + delta
    guard state.tabs.indices.contains(target), state.tabs[target].isClosable else { return nil }
    return target
  }

  @MainActor
  private static func move(_ context: CommandContext, by delta: Int) {
    guard let tab = context.state.selectedTab, let target = movableTarget(context.state, by: delta)
    else { return }
    context.state.move(tab.id, to: target)
    context.say("Moved \(tab.title) to position \(target + 1)")
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
