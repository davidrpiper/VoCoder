// A bare-bones shell over `AppState` for `vocoder --demo` until the real chrome (P1-07): tab
// bar with badges, the selected tab, attention items, and the modules' commands as a list
// (Enter runs one through the keyboard controller). P1-07 replaces it.
import VoCoderCore

public struct DevShell: View {
  public static let commandListID: FocusID = "devshell.commands"

  let state: AppState
  let commands: [Command]
  let commandList: ListState
  let onRun: @MainActor (Command) -> Void

  public init(
    state: AppState, commands: [Command], commandList: ListState,
    onRun: @escaping @MainActor (Command) -> Void
  ) {
    self.state = state
    self.commands = commands
    self.commandList = commandList
    self.onRun = onRun
  }

  public var body: some View {
    VStack {
      TabBar(tabTitles, selected: selectedIndex)
      Divider()
      if let tab = state.selectedTab {
        TabContent(tab).flex()
      } else {
        Text("No tabs").foreground(.muted).centered().flex()
      }
      HStack {
        attentionPanel.flex()
        commandPanel.flex()
      }
      .frame(height: .exactly(7))
      if !state.issues.isEmpty {
        Text("⚠ " + state.issues.map(\.description).joined(separator: " · ")).foreground(.danger)
      }
      Text("demo · ^Space leader · ^P palette · ? help · Tab focus · Enter run · q quit")
        .dim()
    }
  }

  private var tabTitles: [String] {
    state.tabs.enumerated().map { index, tab in
      let badge = tab.badge.label
      return "\(index + 1) \(tab.title)" + (badge.isEmpty ? "" : " \(badge)")
    }
  }

  private var selectedIndex: Int {
    state.tabs.firstIndex { $0.id == state.selectedTabID } ?? 0
  }

  private var attentionPanel: some View {
    VStack {
      if state.attention.isEmpty {
        Text("nothing needs you").foreground(.muted)
      }
      for item in state.attention.reversed() {
        HStack {
          Text(Self.marker(item.priority)).foreground(Self.color(item.priority))
          Text(" " + item.title)
        }
      }
    }
    .border(.rounded, title: "Attention (\(state.attention.count))", color: .border)
  }

  private var commandPanel: some View {
    ContextReader { context in
      ListView(
        Self.commandListID, state: commandList, items: commands,
        onActivate: { onRun(commands[$0]) }
      ) { command, row in
        HStack {
          Text(row.isSelected ? "› " : "  ")
          Text(command.title)
          Spacer()
          Text(command.id.rawValue + " ").foreground(.muted)
        }
      }
      .border(
        .rounded, title: "Commands",
        color: context.containsFocus(Self.commandListID) ? .focus : .border)
    }
  }

  private static func marker(_ priority: AttentionPriority) -> String {
    switch priority {
    case .interrupt: "!"
    case .soon: "•"
    case .ambient: "·"
    }
  }

  private static func color(_ priority: AttentionPriority) -> Color {
    switch priority {
    case .interrupt: .danger
    case .soon: .warning
    case .ambient: .muted
    }
  }
}
