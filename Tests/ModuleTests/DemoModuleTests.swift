import DemoModule
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

/// `vocoder --demo` end to end, minus the terminal (wired like `DemoApp`): the demo module's
/// tab, commands and attention items reach the app state and the screen, and commands run from
/// the shell's list, the leader and the palette.
@MainActor
@Suite struct DemoModuleTests {
  let core = AppCore(
    modules: [DemoModule.self], environment: ModuleEnvironment(secrets: InMemorySecretStore()))
  let commandList = ListState()
  let host = UIHost(theme: .dark)
  let keyboard: KeyboardController
  let quitFlag = QuitFlag()

  init() {
    let core = core
    let commandList = commandList
    let quitFlag = quitFlag
    let keyboard = KeyboardController(
      host: host, dispatcher: core.dispatcher,
      overrides: KeyBindingOverrides(bindings: [NavigationCommands.quit: ["q"]]),
      quit: { quitFlag.quit = true })
    self.keyboard = keyboard
    host.setContent {
      DevShell(
        state: core.state, commands: core.registry.commands, commandList: commandList,
        onRun: { keyboard.invoke($0.id, source: .program) }
      )
      .commandOverlays(keyboard)
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
    #expect(
      core.registry.commands.map(\.id) == [
        "demo.ping", "demo.cycleBadge", "demo.clearAttention", "demo.note", "demo.selectIssue",
      ])
    #expect(core.state.issues.isEmpty)
    #expect(keyboard.keymap.issues.isEmpty)
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

  @Test func leaderAndPaletteRunDemoCommands() async {
    #expect(await eventually { core.state.attention.count == 1 })
    type("\0")
    assertSnapshot(of: host, width: 80, height: 24, named: "which-key")
    type("d")
    type("p")  // <leader> d p: Ping
    #expect(await eventually { core.state.attention.count == 2 })
    type("\0")
    type("2")  // <leader> 2: the Tasks tab
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

    type("q")
    #expect(quitFlag.quit)
    core.stop()
  }
}
