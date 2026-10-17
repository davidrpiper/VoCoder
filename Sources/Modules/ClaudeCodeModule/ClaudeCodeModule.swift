// Filled in by P1-09 (DESIGN §4.10). Modules depend on Core (and UI); never on each other.
// P1-06 adds the config section and the `vocoder doctor` check of the `claude` CLI.
import Foundation
import VoCoderCore
import VoCoderUI

/// Registers its doctor check; the agent backend arrives in P1-09.
public final class ClaudeCodeModule: VoCoderModule {
  public static let id: ModuleID = "claude-code"
  public static let configSection: (any ConfigSection.Type)? = ClaudeCodeConfig.self
  /// The oldest CLI the stream-json host protocol was verified with (P0-04 spike, ADR 0002).
  /// P1-09 confirms it with the replay tests.
  public static let minimumCLIVersion = CLIVersion("2.1.302")!

  public let config: ClaudeCodeConfig

  public init(context: ModuleContext) {
    config = context.config(ClaudeCodeConfig.self) ?? ClaudeCodeConfig()
  }

  public func register(into registry: inout ModuleRegistry) {
    registry.add(doctorCheck: ClaudeCLICheck(minimum: Self.minimumCLIVersion))
  }
}

/// `[claude-code]` in the config file.
public struct ClaudeCodeConfig: ConfigSection, Equatable {
  /// Whether sessions load the user's own MCP servers (ADR 0002): `none` passes
  /// `--strict-mcp-config` with an empty set, `user` loads the user's Claude Code config.
  public enum MCPServers: String, Sendable, CaseIterable {
    case none, user
  }

  public var mcpServers: MCPServers

  public static let keys: [String]? = ["mcp_servers"]

  enum CodingKeys: String, CodingKey {
    case mcpServers = "mcp_servers"
  }

  public init(mcpServers: MCPServers = .none) { self.mcpServers = mcpServers }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let raw = try container.decodeIfPresent(String.self, forKey: .mcpServers) else {
      mcpServers = .none
      return
    }
    guard let value = MCPServers(rawValue: raw) else {
      throw DecodingError.dataCorruptedError(
        forKey: .mcpServers, in: container,
        debugDescription: "'\(raw)' isn't one of: "
          + MCPServers.allCases.map(\.rawValue).joined(separator: ", "))
    }
    mcpServers = value
  }
}

/// A dotted numeric version (`2.1.302`).
public struct CLIVersion: Comparable, Sendable, CustomStringConvertible {
  public let components: [Int]

  public init?(_ text: String) {
    let parts = text.split(separator: ".").map { Int($0) }
    guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
    components = parts.compactMap { $0 }
  }

  /// The version in `claude --version` output (`2.1.302 (Claude Code)`).
  public init?(versionOutput: String) {
    guard let first = versionOutput.split(whereSeparator: \.isWhitespace).first else { return nil }
    self.init(String(first))
  }

  public var description: String { components.map(String.init).joined(separator: ".") }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    let (left, right) = padded(lhs, rhs)
    return left.lexicographicallyPrecedes(right)
  }

  /// `2.1` equals `2.1.0`.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    let (left, right) = padded(lhs, rhs)
    return left == right
  }

  private static func padded(_ lhs: Self, _ rhs: Self) -> ([Int], [Int]) {
    let count = max(lhs.components.count, rhs.components.count)
    let pad = { (version: Self) in
      version.components + Array(repeating: 0, count: count - version.components.count)
    }
    return (pad(lhs), pad(rhs))
  }
}

/// `vocoder doctor`: the `claude` CLI is installed and new enough.
public struct ClaudeCLICheck: DoctorCheck {
  public let id: ProviderID = "claude-code.cli"
  public let title = "Claude Code CLI"
  let minimum: CLIVersion
  let locate: @Sendable () -> URL?
  let versionOutput: @Sendable (URL) async -> String?

  public init(
    minimum: CLIVersion,
    locate: @escaping @Sendable () -> URL? = { ClaudeCLICheck.findExecutable() },
    versionOutput: @escaping @Sendable (URL) async -> String? = {
      await ClaudeCLICheck.versionOutput(of: $0)
    }
  ) {
    self.minimum = minimum
    self.locate = locate
    self.versionOutput = versionOutput
  }

  public func run() async -> DoctorResult {
    guard let url = locate() else {
      return .failure(
        "`claude` not found on PATH",
        hint: "install Claude Code (https://claude.com/claude-code), then `claude` once to log in")
    }
    guard let output = await versionOutput(url), let version = CLIVersion(versionOutput: output)
    else {
      return .failure(
        "\(url.path) --version gave no version",
        hint: "reinstall Claude Code or check `claude --version`")
    }
    guard version >= minimum else {
      return .failure(
        "\(version) is older than \(minimum)", hint: "update it: `claude update`")
    }
    return .ok("\(version) at \(url.path)")
  }

  /// `claude` on `PATH`, or in the installer's usual places.
  public static func findExecutable(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL? {
    let path = (environment["PATH"] ?? "").split(separator: ":").map { URL(filePath: String($0)) }
    let fallbacks = [
      home.appending(path: ".local/bin"), home.appending(path: ".claude/local"),
      URL(filePath: "/opt/homebrew/bin"), URL(filePath: "/usr/local/bin"),
    ]
    return (path + fallbacks).map { $0.appending(path: "claude") }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  /// Runs `claude --version` without the variables that make it a nested Claude Code session.
  public static func versionOutput(of executable: URL) async -> String? {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["--version"]
    process.environment = ProcessInfo.processInfo.environment.filter {
      $0.key != "CLAUDECODE" && !$0.key.hasPrefix("CLAUDE_CODE_")
    }
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    return await withCheckedContinuation { continuation in
      process.terminationHandler = { process in
        let data = output.fileHandleForReading.readDataToEndOfFile()
        continuation.resume(
          returning: process.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil)
      }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(returning: nil)
      }
    }
  }
}
