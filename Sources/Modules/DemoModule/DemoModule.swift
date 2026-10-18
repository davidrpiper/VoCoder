// `vocoder --demo` (DESIGN §4.10 "fakes first"): contributes tabs, commands, an attention source
// and fake providers so the app runs without accounts or network. The only module that may use
// `VoCoderFakes`. Its fake agent and fake repositories back the real repo tab (`RepoModule`),
// which the demo loads too, over `DemoModule.repos`.
import Foundation
import Observation
import VoCoderCore
import VoCoderFakes
import VoCoderUI

public final class DemoModule: VoCoderModule {
  public static let id: ModuleID = "demo"

  /// The demo's repo roots (they don't exist on disk; the fake source control has them).
  public static let repos = [
    RepoRoot(url: URL(filePath: "/demo/vocoder-demo"), aliases: ["the demo repo"])
  ]

  private let tasksTab = DemoTasksTab()
  private let attention = FakeAttentionSource(id: "demo-attention")
  private let sourceControl = FakeSourceControl(id: "demo-vcs")
  private let agent: FakeAgentBackend
  /// Pause between streamed words and steps of the demo agent (tests set zero).
  public static var agentPace = Duration.milliseconds(40)

  public init(context: ModuleContext) {
    agent = FakeAgentBackend(
      id: "demo-agent", displayName: "Demo agent",
      behavior: DemoAgent.behavior(pace: Self.agentPace))
    for root in context.repos { DemoAgent.makeRepository(in: sourceControl, at: root.url) }
    attention.post(
      AttentionItem(
        id: "demo.loaded", source: attention.id, priority: .ambient,
        title: "Demo module loaded", spoken: "The demo module is running."))
  }

  public func register(into registry: inout ModuleRegistry) {
    let tasksTab = tasksTab
    registry.add(agent: agent)
    registry.add(sourceControl: sourceControl)
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
        id: "demo.triage", title: "Set issue status", category: "Demo",
        keys: ["<leader> d t"], isAvailable: { $0.state.selectedTabID == tasksTab.id }
      ) { context in
        guard let index = tasksTab.list.selectedIndex(count: tasksTab.issues.count) else {
          return
        }
        let issue = tasksTab.issues[index]
        let request = ChoiceRequest(
          title: "\(issue.key) status",
          choices: DemoTasksTab.statuses.map { .init(value: $0, title: $0) })
        guard let status = await context.prompter.choose(request) else { return }
        tasksTab.issues[index].status = status
        context.prompter.notify(Notice("\(issue.key) is now \(status)", kind: .success))
        context.say("\(issue.key) is now \(status)")
      },
      Command(
        id: "demo.publish", title: "Publish the demo", category: "Demo",
        keys: ["<leader> d u"], risk: .outward
      ) { context in
        tasksTab.published += 1
        attention.post(
          AttentionItem(
            id: AttentionItemID("demo.publish.\(tasksTab.published)"), source: attention.id,
            priority: .soon, title: "Published the demo"))
        context.prompter.notify(Notice("Published", kind: .success))
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
              tasksTab.issues.map { .init(value: $0.key, title: "\($0.key) \($0.title)") }
            })
        ]
      ) { context in
        guard let key = context.arguments.text("issue"),
          let index = tasksTab.issues.firstIndex(where: { $0.key == key })
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

/// An integration-style tab with a list; its badge counts pings.
@MainActor
@Observable
final class DemoTasksTab: ViewTab {
  static let listID: FocusID = "demo.tasks.list"

  let id: TabID = "demo.tasks"
  let title = "Tasks"
  let hintCommands: [CommandID] = ["demo.triage", "demo.ping"]
  var pings = 0
  var notes = 0
  var published = 0
  let list = ListState()
  var issues: [(key: String, title: String, status: String)] = [
    ("DEMO-1", "Wire the module system", "Done"),
    ("DEMO-2", "Command palette", "Done"),
    ("DEMO-3", "App chrome", "In Progress"),
    ("DEMO-4", "Repo tab", "Backlog"),
  ]
  static let statuses = ["Backlog", "Todo", "In Progress", "In Review", "Done"]

  var badge: TabBadge { .count(pings) }

  var body: some View {
    ListView(Self.listID, state: list, items: issues) { issue, row in
      HStack {
        Text(row.isSelected ? "› " : "  ")
        Text(issue.key).foreground(.accent)
        Text(" " + issue.title)
        Spacer()
        Text(issue.status + " ").foreground(.muted)
      }
    }
    .border(.rounded, title: "Demo tasks", color: .border)
  }
}
