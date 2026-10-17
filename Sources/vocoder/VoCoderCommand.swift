import ArgumentParser
import VoCoderCore

@main
struct VoCoderCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "vocoder",
    abstract: "Voice-first TUI workspace.",
    version: BuildInfo.fromMainBundle()?.displayString ?? "unknown (no embedded Info.plist)",
    subcommands: [BridgeDemoCommand.self, UIGalleryCommand.self]
  )

  func run() throws {
    Log.bootstrap(sink: FileLogSink(directory: Log.defaultDirectory))
    let log = Log(category: "app")
    log.info("vocoder \(BuildInfo.fromMainBundle()?.displayString ?? "unknown") started")
    // The TUI arrives with P1-07; until then there is nothing to run (`bridge-demo` exercises
    // the UI bridge).
    print("VoCoder scaffold — the TUI is not built yet. See docs/PROGRESS.md.")
    log.info("vocoder exiting")
  }
}
