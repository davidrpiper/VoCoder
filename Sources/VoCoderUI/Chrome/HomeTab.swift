// The Home tab (DESIGN §3.2), built into the chrome: always first and can't be closed. A
// placeholder until P3-04 brings the daily briefing: for now it shows the attention items as an
// inbox, problems found while loading modules, and how to get around.
import Observation
import VoCoderCore

@MainActor
@Observable
public final class HomeTab: ViewTab {
  public static let tabID: TabID = "home"
  public static let inboxID: FocusID = "home.inbox"

  public let id = HomeTab.tabID
  public let title = "Home"
  public let aliases = ["home"]
  public var isClosable: Bool { false }
  public let inbox = ListState()
  private let state: AppState

  public init(state: AppState) { self.state = state }

  public var badge: TabBadge { .count(state.attention.count) }

  /// The factory the app passes to `AppCore` as a built-in tab.
  public var factory: TabFactory {
    TabFactory(id: "core.home", placement: .home) { [self] _ in [self] }
  }

  public var body: some View {
    let items = inboxItems
    VStack {
      ContextReader { context in
        ListView(
          Self.inboxID, state: self.inbox, items: items, emptyText: "Nothing needs you."
        ) { item, row in
          HStack {
            Text(row.isSelected && row.listFocused ? "› " : "  ")
            Text(Self.marker(item.priority) + " ").foreground(Self.color(item.priority))
            Text(item.title)
            Spacer()
          }
        }
        .border(
          .rounded, title: "Needs you (\(items.count))",
          color: context.containsFocus(Self.inboxID) ? .focus : .border)
      }
      .flex()
      if !state.issues.isEmpty {
        VStack {
          for issue in state.issues {
            Paragraph(issue.description).foreground(.danger)
          }
        }
        .border(.rounded, title: "Problems (\(state.issues.count))", color: .danger)
      }
      VStack {
        Paragraph(
          "The daily briefing arrives with Phase 3. The bar at the bottom shows the main keys;"
            + " the palette finds any command, and help lists them all with their keys.")
      }
      .border(.rounded, title: "Getting around", color: .border)
    }
  }

  /// Most urgent first, newest first within a priority (the queue's policy is P3-01's).
  var inboxItems: [AttentionItem] {
    let rank: (AttentionPriority) -> Int = {
      switch $0 {
      case .interrupt: 0
      case .soon: 1
      case .ambient: 2
      }
    }
    return state.attention.enumerated()
      .sorted { (rank($0.element.priority), -$0.offset) < (rank($1.element.priority), -$1.offset) }
      .map(\.element)
  }

  static func marker(_ priority: AttentionPriority) -> String {
    switch priority {
    case .interrupt: "!"
    case .soon: "•"
    case .ambient: "·"
    }
  }

  static func color(_ priority: AttentionPriority) -> Color {
    switch priority {
    case .interrupt: .danger
    case .soon: .warning
    case .ambient: .muted
    }
  }
}
