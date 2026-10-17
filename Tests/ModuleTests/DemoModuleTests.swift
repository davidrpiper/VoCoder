import DemoModule
import Testing
import VoCoderCore
import VoCoderFakes
import VoCoderTestSupport
import VoCoderUI
import VoCoderUITestSupport

/// `vocoder --demo` end to end, minus the terminal: the demo module's tab, commands and
/// attention items reach the app state and the screen, and commands run from the shell.
@MainActor
@Suite struct DemoModuleTests {
  let core = AppCore(
    modules: [DemoModule.self], environment: ModuleEnvironment(secrets: InMemorySecretStore()))
  let commandList = ListState()
  let host: UIHost

  init() {
    let core = core
    let commandList = commandList
    host = UIHost(theme: .dark) {
      DevShell(
        state: core.state, commands: core.commands.all, commandList: commandList,
        onRun: { command in Task { try? await core.run(command.id) } })
    }
    core.start()
    host.focus.focus(DevShell.commandListID)
    host.render()
  }

  /// Feeds raw terminal bytes through the bridge's parser, delivering events synchronously.
  func type(_ input: String) {
    host.renderer.onEvent = { [host] event in MainActor.assumeIsolated { host.handle(event) } }
    host.renderer.injectInput(input)
    host.renderIfNeeded()
  }

  @Test func contributionsAppearOnScreen() async {
    #expect(core.state.tabs.map(\.title) == ["demo-repo", "Tasks"])
    #expect(core.commands.all.map(\.id) == ["demo.ping", "demo.cycleBadge", "demo.clearAttention"])
    #expect(await eventually { core.state.attention.count == 1 })
    assertSnapshot(of: host, width: 80, height: 24)
    core.stop()
  }

  @Test func commandsRunFromTheShell() async {
    #expect(await eventually { core.state.attention.count == 1 })
    type("\r")  // Ping
    #expect(await eventually { core.state.attention.count == 2 })
    #expect(core.state.tabs.last?.badge == .count(1))
    type("j\r")  // Cycle repo badge
    #expect(await eventually { core.state.tabs.first?.badge == .needsYou })
    core.state.select("demo.tasks")
    assertSnapshot(of: host, width: 80, height: 24)
    type("j\r")  // Clear attention
    #expect(await eventually { core.state.attention.isEmpty })
    core.stop()
  }
}
