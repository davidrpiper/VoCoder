// `vocoder --demo`: loads the demo modules and runs them in the dev shell (P1-07 brings the real
// chrome). Keys go through the command keymap; `q` is added to quit as a development override.
import Foundation
import VoCoderCore
import VoCoderFakes
import VoCoderUI

@MainActor
final class DemoApp {
  /// Development keys on top of the defaults.
  static let overrides = KeyBindingOverrides(bindings: [
    NavigationCommands.quit: ["q", "Ctrl-c", "<leader> q"]
  ])

  private let core: AppCore
  private let host: UIHost
  private let keyboard: KeyboardController
  private let commandList = ListState()
  private let log = Log(category: "demo")
  private lazy var runLoop = TerminalRunLoop(renderer: host.renderer, log: log)

  init(theme: Theme) {
    let environment = ModuleEnvironment(secrets: InMemorySecretStore())
    let core = AppCore(modules: CompiledModules.demo, environment: environment)
    let host = UIHost(theme: theme)
    let keyboard = KeyboardController(
      host: host, dispatcher: core.dispatcher, overrides: Self.overrides,
      quit: { [weak host] in host?.renderer.stop() })
    let commandList = commandList
    host.setContent {
      DevShell(
        state: core.state, commands: core.registry.commands, commandList: commandList,
        onRun: { keyboard.invoke($0.id, source: .program) }
      )
      .commandOverlays(keyboard)
    }
    self.core = core
    self.host = host
    self.keyboard = keyboard
  }

  func run() {
    core.start()
    host.connect()
    host.focus.focus(DevShell.commandListID)
    host.render()
    log.info("demo started")
    runLoop.run()
    core.stop()
    log.info("demo exited")
  }
}
