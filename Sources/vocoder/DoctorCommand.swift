// `vocoder doctor` (DESIGN §4.9, ADR 0009): Core's, the app's and the modules' checks, one line
// each with a fix hint. Loads the modules exactly as the app would (same config, Keychain and
// key overrides) without starting them or taking over the terminal.
import ArgumentParser
import Foundation
import FoundationModels
import Synchronization
import VoCoderCore
import VoCoderUI

struct DoctorCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Check the setup: config, terminal, keys, Apple Intelligence, CLIs and secrets."
  )

  @OptionGroup var options: ConfigOptions

  func run() throws {
    Log.bootstrap(sink: FileLogSink(directory: Log.defaultDirectory))
    let options = options
    let checks = MainActor.assumeIsolated { Self.checks(options) }
    let report = Self.wait { await Doctor.run(checks) }
    print(report.rendered(colors: isatty(STDOUT_FILENO) == 1))
    Log(category: "doctor").info("doctor: worst result \(report.worst)")
    if report.worst == .failure { throw ExitCode.failure }
  }

  @MainActor
  static func checks(_ options: ConfigOptions) -> [(owner: ModuleID, check: any DoctorCheck)] {
    let loaded = options.load()
    let config = loaded.config
    let store = KeychainSecretStore()
    let modules = config.enabled(CompiledModules.all)
    let shell = AppShell(
      modules: modules, environment: config.environment(for: CompiledModules.all, secrets: store),
      host: UIHost(), overrides: config.keys, quit: {})

    var checks: [(ModuleID, any DoctorCheck)] = [("core", CoreDoctorChecks.config(loaded))]
    let terminal = TerminalEnvironment.current()
    for check in TerminalDoctorChecks.all(terminal, leader: config.keys.leader ?? .leaderDefault) {
      checks.append(("app", check))
    }
    checks.append(("app", appleIntelligence))
    checks.append(
      (
        "core",
        CoreDoctorChecks.modules(loaded: shell.core.state.modules, issues: shell.core.state.issues)
      ))
    checks.append(("core", CoreDoctorChecks.keymap(issues: shell.keyboard.keymap.issues)))
    checks.append(
      ("core", CoreDoctorChecks.secrets(modules: modules.map { ($0.id, $0.secrets) }, store: store))
    )
    let registry = shell.core.registry
    for check in registry.doctorChecks {
      checks.append((registry.owner(of: check.id.rawValue, in: .doctorChecks) ?? "unknown", check))
    }
    return checks
  }

  /// On-device model availability (ADR 0003). Moves into the Foundation Models module with
  /// P2-05.
  static let appleIntelligence = ClosureDoctorCheck(
    id: "app.apple-intelligence", title: "Apple Intelligence"
  ) {
    let later = "needed for voice commands (Phase 2)"
    switch SystemLanguageModel.default.availability {
    case .available:
      return .ok("on-device model available")
    case .unavailable(.appleIntelligenceNotEnabled):
      return .warning(
        "turned off; \(later)", hint: "System Settings → Apple Intelligence & Siri → turn it on")
    case .unavailable(.modelNotReady):
      return .warning(
        "the model is still downloading; \(later)",
        hint: "keep the Mac on power and online, then check again")
    case .unavailable(.deviceNotEligible):
      return .warning("this Mac can't run it; \(later)", hint: "voice needs an Apple Silicon Mac")
    case .unavailable(let reason):
      return .warning(
        "unavailable (\(reason)); \(later)",
        hint: "check System Settings → Apple Intelligence & Siri")
    }
  }

  /// Runs `body` while keeping the main run loop going (checks may hop to the main actor).
  static func wait<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let result = Box(Mutex<T?>(nil))
    Task {
      let value = await body()
      result.value.withLock { $0 = value }
    }
    while true {
      if let value = result.value.withLock({ $0 }) { return value }
      RunLoop.main.run(mode: .default, before: .now + 0.01)
    }
  }
}

/// Shares a `Mutex` (non-copyable) with a task.
private final class Box<Value: ~Copyable & Sendable>: Sendable {
  let value: Value
  init(_ value: consuming Value) { self.value = value }
}
