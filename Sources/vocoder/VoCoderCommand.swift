import ArgumentParser
import VoCoderCore
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
    if demo {
      MainActor.assumeIsolated { DemoApp(theme: .automatic()).run() }
      return
    }
    // The TUI arrives with P1-07; until then only `--demo` runs one (`bridge-demo` and
    // `ui-gallery` exercise the UI layers).
    print("VoCoder scaffold — the TUI is not built yet; try `vocoder --demo`.")
    log.info("vocoder exiting")
  }
}
