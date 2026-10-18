import ArgumentParser
import DemoModule
import Foundation
import VoCoderCore
import VoCoderFakes
import VoCoderUI

@main
struct VoCoderCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "vocoder",
    abstract: "Voice-first TUI workspace.",
    version: BuildInfo.fromMainBundle()?.displayString ?? "unknown (no embedded Info.plist)",
    subcommands: [
      AuthCommand.self, ConfigCommand.self, DoctorCommand.self, BridgeDemoCommand.self,
      UIGalleryCommand.self,
    ]
  )

  @Flag(help: "Run with fake demo modules (no accounts or network).") var demo = false
  @OptionGroup var options: ConfigOptions

  func run() throws {
    Log.bootstrap(sink: FileLogSink(directory: Log.defaultDirectory))
    let log = Log(category: "app")
    log.info("vocoder \(BuildInfo.fromMainBundle()?.displayString ?? "unknown") started")
    let demo = demo
    let options = options
    try MainActor.assumeIsolated {
      let loaded = options.load()
      // Config errors stop startup, before the TUI takes the terminal (ADR 0009).
      guard loaded.isValid else {
        ConfigOptions.printErrors(loaded)
        log.error("config invalid: \(loaded.errors.count) errors")
        throw ExitCode.failure
      }
      let modules = demo ? CompiledModules.demo : CompiledModules.all
      let secrets: any SecretStore = demo ? InMemorySecretStore() : KeychainSecretStore()
      let notice =
        loaded.exists || demo
        ? nil : Notice("No config file: run `vocoder config init` to add repos", kind: .info)
      var environment = loaded.config.environment(for: modules, secrets: secrets)
      if demo {
        environment.repos = DemoModule.repos
      } else {
        environment.services.agentSessions = AgentSessionStore()
      }
      VoCoderApp(
        modules: modules,
        environment: environment,
        theme: .preferred(loaded.config.theme), overrides: loaded.config.keys, notice: notice
      ).run()
    }
    log.info("vocoder exiting")
  }
}

/// `--config`, shared by the commands that read the config file.
struct ConfigOptions: ParsableArguments {
  @Option(
    name: .customLong("config"),
    help: "Config file (default: $VOCODER_CONFIG, then ~/.config/vocoder/config.toml).")
  var path: String?

  var url: URL { ConfigLoader.location(explicit: path) }

  /// Loads and validates the config against every compiled-in module.
  @MainActor
  func load() -> ConfigLoadResult {
    ConfigLoader.load(from: url, modules: CompiledModules.known, required: path != nil)
  }

  static func printErrors(_ result: ConfigLoadResult) {
    let count = result.errors.count
    var text = "vocoder: \(count) problem\(count == 1 ? "" : "s") in \(result.displayPath):\n"
    for error in result.errors {
      text += "  " + error.description.replacing("\n", with: "\n  ") + "\n"
    }
    text += "Fix \(count == 1 ? "it" : "them") and run `vocoder config check`.\n"
    FileHandle.standardError.write(Data(text.utf8))
  }
}
