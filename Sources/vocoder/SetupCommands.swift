// Setup outside the TUI (DESIGN §4.9, ADR 0009): `vocoder auth <module>` stores a module's
// secrets in the Keychain; `vocoder config init|check` writes and validates the config file.
import ArgumentParser
import Darwin
import Foundation
import VoCoderCore

struct AuthCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "auth",
    abstract: "Store a module's secrets (API keys, tokens) in the Keychain."
  )

  @Argument(help: "The module, e.g. linear or notion.") var module: String
  @Flag(help: "Read the secrets from standard input, one per line (for scripts).")
  var stdin = false
  @Flag(help: "Remove the module's secrets instead.") var remove = false

  func run() throws {
    Log.bootstrap(sink: FileLogSink(directory: Log.defaultDirectory))
    let (id, specs) = try MainActor.assumeIsolated { () throws -> (ModuleID, [SecretSpec]) in
      let withSecrets = CompiledModules.all.filter { !$0.secrets.isEmpty }.map { $0.id.rawValue }
      guard let type = CompiledModules.named(module) else {
        throw SetupError(
          "unknown module '\(module)'; modules with secrets: \(withSecrets.joined(separator: ", "))"
        )
      }
      guard !type.secrets.isEmpty else {
        throw SetupError(
          "the \(module) module needs no secrets; modules with secrets: "
            + withSecrets.joined(separator: ", "))
      }
      return (type.id, type.secrets)
    }
    let store = KeychainSecretStore()
    if remove {
      for (spec, _) in try SecretSetup.remove(specs, module: id, from: store) {
        print("Removed \(spec.title).")
      }
      return
    }
    let stdin = stdin
    let outcomes = try SecretSetup.store(specs, module: id, in: store) { spec in
      if stdin { return readLine(strippingNewline: true) }
      print("\(spec.title) (\(spec.help))")
      return Self.readSecret(prompt: "\(spec.title): ")
    }
    for (spec, outcome) in outcomes {
      switch outcome {
      case .stored:
        print(
          "Saved \(spec.title) in the Keychain (\(store.service(for: SecretKey(module: id, name: spec.name))))."
        )
      case .unchanged: print("\(spec.title): nothing entered, left unchanged.")
      case .removed: break
      }
    }
  }

  /// Reads a line from the terminal without echoing it.
  static func readSecret(prompt: String) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    defer { _ = buffer.withUnsafeMutableBytes { memset_s($0.baseAddress, $0.count, 0, $0.count) } }
    guard readpassphrase(prompt, &buffer, buffer.count, RPP_ECHO_OFF | RPP_REQUIRE_TTY) != nil
    else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }
}

struct ConfigCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: "Create or check the config file.",
    subcommands: [Init.self, Check.self]
  )

  struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Write a commented config file to start from.")

    @OptionGroup var options: ConfigOptions
    @Flag(help: "Replace an existing file.") var force = false

    func run() throws {
      let url = options.url
      let shown = ConfigLoader.displayPath(
        url, home: FileManager.default.homeDirectoryForCurrentUser)
      if FileManager.default.fileExists(atPath: url.path) && !force {
        throw SetupError("\(shown) already exists; pass --force to replace it")
      }
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(ConfigTemplate.text.utf8).write(to: url, options: .atomic)
      print("Wrote \(shown). Add your repos, then run `vocoder config check` and `vocoder doctor`.")
    }
  }

  struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Validate the config file.")

    @OptionGroup var options: ConfigOptions

    func run() throws {
      let options = options
      try MainActor.assumeIsolated {
        let result = options.load()
        guard result.isValid else {
          ConfigOptions.printErrors(result)
          throw ExitCode.failure
        }
        guard result.exists else {
          print(
            "No config file at \(result.displayPath); defaults apply. Create one with `vocoder config init`."
          )
          return
        }
        let config = result.config
        var parts = ["\(config.repos.count) repo\(config.repos.count == 1 ? "" : "s")"]
        if !config.keys.bindings.isEmpty || (config.keys.leader ?? .leaderDefault) != .leaderDefault
        {
          parts.append("key overrides")
        }
        if !config.disabledModules.isEmpty {
          parts.append(
            "disabled: " + config.disabledModules.sorted().map(\.rawValue).joined(separator: ", "))
        }
        print("\(result.displayPath) is valid (\(parts.joined(separator: "; "))).")
      }
    }
  }
}

/// A setup problem: printed as `Error: …` without the usage text (the arguments were fine).
struct SetupError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
