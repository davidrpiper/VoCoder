import ArgumentParser
import VoCoderCore
import VoCoderFakes
import VoCoderUI

@main
struct VoCoderCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "vocoder",
    abstract: "Voice-first TUI workspace.",
    version: BuildInfo.fromMainBundle()?.displayString ?? "unknown (no embedded Info.plist)",
    subcommands: [BridgeDemoCommand.self, UIGalleryCommand.self]
  )

  @Flag(help: "Run with fake demo modules (no accounts or network).") var demo = false

  func run() throws {
    Log.bootstrap(sink: FileLogSink(directory: Log.defaultDirectory))
    let log = Log(category: "app")
    log.info("vocoder \(BuildInfo.fromMainBundle()?.displayString ?? "unknown") started")
    // Config, repos and the Keychain arrive with P1-06; until then the real modules load
    // without configuration (only Home has content) and secrets stay in memory.
    MainActor.assumeIsolated {
      let environment = ModuleEnvironment(secrets: InMemorySecretStore())
      VoCoderApp(
        modules: demo ? CompiledModules.demo : CompiledModules.all, environment: environment,
        theme: .automatic()
      ).run()
    }
    log.info("vocoder exiting")
  }
}
