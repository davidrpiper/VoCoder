// The app: the chrome (`AppShell`) over the compiled modules, on the terminal session. `vocoder`
// runs the enabled real modules under the config; `vocoder --demo` the fake-backed demo module.
import Foundation
import VoCoderCore
import VoCoderUI

@MainActor
final class VoCoderApp {
  private let shell: AppShell
  private let session: TerminalSession
  private let notice: Notice?
  private let log = Log(category: "app")

  init(
    modules: [any VoCoderModule.Type], environment: ModuleEnvironment, theme: Theme,
    overrides: KeyBindingOverrides = KeyBindingOverrides(), notice: Notice? = nil
  ) {
    let host = UIHost(theme: theme)
    shell = AppShell(
      modules: modules, environment: environment, host: host, overrides: overrides,
      quit: { [weak host] in host?.renderer.stop() })
    session = TerminalSession(renderer: host.renderer, log: log)
    self.notice = notice
  }

  func run() {
    shell.host.connect()
    shell.start()
    if let notice { shell.toasts.show(notice) }
    log.info("tui started")
    session.run()
    shell.stop()
    log.info("tui exited")
  }
}
