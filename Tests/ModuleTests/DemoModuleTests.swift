import DemoModule
import RepoModule
import Testing
import VoCoderCore
import VoCoderFakes
import VoCoderTestSupport
import VoCoderUI
import VoCoderUITestSupport

@MainActor
final class QuitFlag {
  var quit = false
}

/// `vocoder --demo` end to end, minus the terminal (wired like `VoCoderApp`): the demo module's
/// tabs, commands and attention items reach the chrome, commands run from the leader, the
/// palette and the modals they open, and the repo tab runs a turn on the demo agent.
@MainActor
@Suite struct DemoModuleTests {
  let host = UIHost(theme: .dark)
  let shell: AppShell
  let quitFlag = QuitFlag()
  var core: AppCore { shell.core }
  var keyboard: KeyboardController { shell.keyboard }

  init() {
    let quitFlag = quitFlag
    DemoModule.agentPace = .zero
    shell = AppShell(
      modules: [DemoModule.self, RepoModule.self],
      environment: ModuleEnvironment(secrets: InMemorySecretStore(), repos: DemoModule.repos),
      host: host,
      quit: { quitFlag.quit = true })
    shell.toasts.sleep = { _ in try await Task.sleep(for: .seconds(3600)) }
    shell.start()
  }

  /// Feeds raw terminal bytes through the bridge's parser, delivering events synchronously.
  func type(_ input: String) {
    host.renderer.onEvent = { [host] event in MainActor.assumeIsolated { host.handle(event) } }
    host.renderer.injectInput(input)
    host.renderIfNeeded()
  }

  @Test func contributionsAppearOnScreen() async {
    #expect(core.state.tabs.map(\.title) == ["Home", "vocoder-demo", "Tasks"])
    #expect(
      core.registry.commands.map(\.id).filter { $0.rawValue.hasPrefix("demo.") } == [
        "demo.ping", "demo.clearAttention", "demo.triage", "demo.publish", "demo.note",
        "demo.selectIssue",
      ])
    #expect(core.state.issues.isEmpty)
    #expect(keyboard.keymap.issues.isEmpty)
    #expect(await eventually { core.state.attention.count == 1 })
    assertSnapshot(of: host, width: 80, height: 24)
    core.stop()
  }

  @Test func commandsRunFromTheLeader() async {
    #expect(await eventually { core.state.attention.count == 1 })
    type("\0dp")  // Ping
    #expect(await eventually { core.state.attention.count == 2 })
    #expect(core.state.tabs.last?.badge == .count(1))
    core.state.select("demo.tasks")
    assertSnapshot(of: host, width: 80, height: 24)
    type("\0dc")  // Clear attention
    #expect(await eventually { core.state.attention.isEmpty })
    core.stop()
  }

  @Test func demoCommandsUseTheModals() async {
    type("\02")  // the repo tab: focus goes to the prompt
    host.render()
    type("what changed?\r")
    #expect(await eventually { core.state.tabs[1].badge == .needsYou })
    assertSnapshot(of: host, width: 80, height: 24, named: "approval")
    type("a")  // approve once
    #expect(await eventually { core.state.tabs[1].badge == TabBadge.none })
    assertSnapshot(of: host, width: 80, height: 24, named: "answered")

    type("\03")  // the Tasks tab
    type("jj")  // DEMO-3
    type("\0dt")  // Triage: a list picker
    type("review\r")
    #expect(
      await eventually { shell.toasts.toasts.map(\.notice.message) == ["DEMO-3 is now In Review"] })
    assertSnapshot(of: host, width: 80, height: 24, named: "triaged")

    type("\0du")  // Publish: outward, confirm first
    #expect(shell.modals.top != nil)
    type("y")
    #expect(await eventually { core.state.attention.map(\.title).last == "Published the demo" })
    core.stop()
  }

  @Test func leaderAndPaletteRunDemoCommands() async {
    #expect(await eventually { core.state.attention.count == 1 })
    type("\0")
    assertSnapshot(of: host, width: 80, height: 24, named: "which-key")
    type("d")
    type("p")  // <leader> d p: Ping
    #expect(await eventually { core.state.attention.count == 2 })
    type("\0")
    type("3")  // <leader> 3: the Tasks tab
    #expect(core.state.selectedTabID == "demo.tasks")

    type("\u{10}")  // Ctrl-P
    type("post note\r")
    type("hello\r")
    #expect(await eventually { core.state.attention.map(\.title).last == "hello" })

    type("\u{10}")
    type("select issue\r")
    type("DEMO-3\r")
    #expect((core.state.selectedTab as? any ViewTab)?.id == "demo.tasks")
    assertSnapshot(of: host, width: 80, height: 24, named: "issue-selected")

    type("\0q")
    #expect(quitFlag.quit)
    core.stop()
  }
}
