// `vocoder --demo` (DESIGN §4.10 "fakes first"): contributes tabs, commands, an attention source
// and fake providers so the app runs without accounts or network. The only module that may use
// `VoCoderFakes`.
import Foundation
import Observation
import VoCoderCore
import VoCoderFakes
import VoCoderUI

public final class DemoModule: VoCoderModule {
  public static let id: ModuleID = "demo"

  private let repoTab = DemoRepoTab()
  private let tasksTab = DemoTasksTab()
  private let attention = FakeAttentionSource(id: "demo-attention")

  public init(context: ModuleContext) {
    attention.post(
      AttentionItem(
        id: "demo.loaded", source: attention.id, priority: .ambient,
        title: "Demo module loaded", spoken: "The demo module is running."))
  }

  public func register(into registry: inout ModuleRegistry) {
    let repoTab = repoTab
    let tasksTab = tasksTab
    registry.add(
      tabs: TabFactory(id: "demo.repo", placement: .repo) { _ in [repoTab] })
    registry.add(
      tabs: TabFactory(id: "demo.tasks", placement: .integration) { _ in [tasksTab] })

    let attention = attention
    registry.add(commands: [
      Command(
        id: "demo.ping", title: "Ping", category: "Demo", keys: ["<leader> d p"],
        voicePhrases: ["ping"]
      ) { context in
        tasksTab.pings += 1
        attention.post(
          AttentionItem(
            id: AttentionItemID("demo.ping.\(tasksTab.pings)"), source: attention.id,
            priority: .soon, title: "Ping \(tasksTab.pings)"))
        context.say("Ping \(tasksTab.pings)")
      },
      Command(
        id: "demo.cycleBadge", title: "Cycle repo badge", category: "Demo",
        keys: ["<leader> d b"]
      ) { _ in
        repoTab.cycleBadge()
      },
      Command(
        id: "demo.clearAttention", title: "Clear attention", category: "Demo",
        keys: ["<leader> d c"], voicePhrases: ["clear attention"], risk: .reversible
      ) { context in
        let cleared = context.state.attention
        for item in cleared { context.state.dismissAttention(item.id) }
        context.offerUndo(
          UndoAction(title: "Restore \(cleared.count) attention items") { [state = context.state] in
            for item in cleared { state.post(item) }
          })
      },
      Command(
        id: "demo.note", title: "Post a note", category: "Demo",
        params: [CommandParameter("text", title: "Note")]
      ) { context in
        let text = context.arguments.text("text") ?? ""
        tasksTab.notes += 1
        attention.post(
          AttentionItem(
            id: AttentionItemID("demo.note.\(tasksTab.notes)"), source: attention.id,
            priority: .ambient, title: text))
      },
      Command(
        id: "demo.selectIssue", title: "Select a demo issue", category: "Demo",
        params: [
          CommandParameter(
            "issue", title: "Issue",
            kind: .choice { _ in
              tasksTab.issues.map { .init(value: $0.0, title: "\($0.0) \($0.1)") }
            })
        ]
      ) { context in
        guard let key = context.arguments.text("issue"),
          let index = tasksTab.issues.firstIndex(where: { $0.0 == key })
        else { return }
        tasksTab.list.selection = index
        context.state.select(tasksTab.id)
      },
    ])
    registry.add(attentionSource: attention)
    registry.add(tracker: FakeTaskTracker(id: "demo-tracker", capabilities: [.iterations]))
    registry.add(languageModel: FakeLanguageModel(id: "demo-model"))
  }
}

/// A repo-style tab whose badge the `demo.cycleBadge` command cycles.
@MainActor
@Observable
final class DemoRepoTab: ViewTab {
  let id: TabID = "demo.repo"
  let title = "demo-repo"
  let aliases = ["the demo repo"]
  private(set) var badge = TabBadge.working
  private(set) var activations = 0

  private static let badges: [TabBadge] = [.working, .needsYou, .finished, .error, .none]

  func cycleBadge() {
    let index = Self.badges.firstIndex(of: badge) ?? 0
    badge = Self.badges[(index + 1) % Self.badges.count]
  }

  func didActivate() { activations += 1 }

  var body: some View {
    VStack {
      Text("Demo repository").bold()
      Paragraph(
        "A stand-in for a repo tab (P1-10). Its badge is \(badge == .none ? "empty" : badge.label);"
          + " run “Cycle repo badge” to change it. Shown \(activations) time(s).")
    }
    .border(.rounded, title: "demo-repo", color: .border)
  }
}

/// An integration-style tab with a list; its badge counts pings.
@MainActor
@Observable
final class DemoTasksTab: ViewTab {
  static let listID: FocusID = "demo.tasks.list"

  let id: TabID = "demo.tasks"
  let title = "Tasks"
  var pings = 0
  var notes = 0
  let list = ListState()
  let issues = [
    ("DEMO-1", "Wire the module system", "Done"),
    ("DEMO-2", "Command palette", "Todo"),
    ("DEMO-3", "App chrome", "Todo"),
    ("DEMO-4", "Repo tab", "Backlog"),
  ]

  var badge: TabBadge { .count(pings) }

  var body: some View {
    ListView(Self.listID, state: list, items: issues) { issue, row in
      HStack {
        Text(row.isSelected ? "› " : "  ")
        Text(issue.0).foreground(.accent)
        Text(" " + issue.1)
        Spacer()
        Text(issue.2 + " ").foreground(.muted)
      }
    }
    .border(.rounded, title: "Demo tasks", color: .border)
  }
}
