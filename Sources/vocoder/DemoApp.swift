// `vocoder --demo`: loads the demo modules and runs them in the dev shell (P1-07 brings the real
// chrome). Tab digits and q are development keys, like the gallery's; they aren't commands.
import Foundation
import VoCoderCore
import VoCoderFakes
import VoCoderUI

@MainActor
final class DemoApp {
  private let core: AppCore
  private let host: UIHost
  private let commandList = ListState()
  private let log = Log(category: "demo")
  private lazy var runLoop = TerminalRunLoop(renderer: host.renderer, log: log)

  init(theme: Theme) {
    let environment = ModuleEnvironment(secrets: InMemorySecretStore())
    let core = AppCore(modules: CompiledModules.demo, environment: environment)
    let commandList = commandList
    let log = log
    self.core = core
    host = UIHost(theme: theme) {
      DevShell(
        state: core.state, commands: core.commands.all, commandList: commandList,
        onRun: { command in
          Task {
            do { try await core.run(command.id) } catch {
              log.error("command \(command.id) failed: \(error)")
            }
          }
        })
    }
    host.onUnhandledKey = { [unowned self] key in self.handleKey(key) }
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

  private func handleKey(_ key: String) -> Bool {
    let tabs = core.state.tabs
    switch key {
    case "q", "Ctrl-c":
      host.renderer.stop()
    case let digit where Int(digit).map({ (1...tabs.count).contains($0) }) == true:
      core.state.select(tabs[Int(digit)! - 1].id)
    default:
      return false
    }
    return true
  }
}
