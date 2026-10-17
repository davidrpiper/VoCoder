import Foundation
import Synchronization
import VoCoderCore

/// Claude Code as an `AgentBackend`: one `claude -p` stream-json process per session, using
/// the user's existing Claude Code login (DESIGN §4.4).
public final class ClaudeCodeBackend: AgentBackend {
  public let id: ProviderID = "claude-code"
  public let displayName = "Claude Code"
  let config: ClaudeCodeConfig
  let minimumVersion: CLIVersion
  let locate: @Sendable () -> URL?
  let versionOutput: @Sendable (URL) async -> String?
  let environment: @Sendable () -> [String: String]
  let launcher: ClaudeLauncher
  let restartDelays: [Duration]
  /// The executable whose version passed, so only the first session pays for `--version`.
  private let checked = Mutex<URL?>(nil)

  public init(
    config: ClaudeCodeConfig = ClaudeCodeConfig(),
    minimumVersion: CLIVersion = ClaudeCodeModule.minimumCLIVersion,
    locate: @escaping @Sendable () -> URL? = { ClaudeCLICheck.findExecutable() },
    versionOutput: @escaping @Sendable (URL) async -> String? = {
      await ClaudeCLICheck.versionOutput(of: $0)
    },
    environment: @escaping @Sendable () -> [String: String] = {
      ProcessInfo.processInfo.environment
    },
    restartDelays: [Duration] = [.milliseconds(500), .seconds(2), .seconds(5)],
    launcher: @escaping ClaudeLauncher = {
      try ProcessTransport.launch($0, log: Log(category: "agent.claude-code"))
    }
  ) {
    self.config = config
    self.minimumVersion = minimumVersion
    self.locate = locate
    self.versionOutput = versionOutput
    self.environment = environment
    self.restartDelays = restartDelays
    self.launcher = launcher
  }

  public func startSession(_ options: AgentSessionOptions) async throws -> any AgentSession {
    guard let executable = locate() else { throw AgentError.executableNotFound("claude") }
    try await checkVersion(of: executable)
    let config = config
    let environment = ClaudeLaunch.sanitized(environment())
    return try await ClaudeCodeSession.start(
      resume: options.resume, minimumVersion: minimumVersion, restartDelays: restartDelays,
      launcher: launcher
    ) { resume in
      ClaudeLaunch(
        executable: executable,
        arguments: ClaudeLaunch.arguments(config: config, model: options.model, resume: resume),
        environment: environment, directory: options.repo)
    }
  }

  private func checkVersion(of executable: URL) async throws {
    guard checked.withLock({ $0 }) != executable else { return }
    guard let output = await versionOutput(executable),
      let version = CLIVersion(versionOutput: output)
    else { throw AgentError.launchFailed("\(executable.path) --version gave no version") }
    guard version >= minimumVersion else {
      throw AgentError.unsupportedVersion(
        found: version.description, minimum: minimumVersion.description)
    }
    checked.withLock { $0 = executable }
  }
}

/// Placeholder for OpenAI Codex: keeps the agent seam honest until a real adapter (DESIGN
/// §4.4). Not registered.
public struct CodexBackend: AgentBackend {
  public let id: ProviderID = "codex"
  public let displayName = "Codex"
  public init() {}

  public func startSession(_ options: AgentSessionOptions) async throws -> any AgentSession {
    throw AgentError.notImplemented(backend: displayName)
  }
}

/// Placeholder for Gemini CLI, like `CodexBackend`. Not registered.
public struct GeminiBackend: AgentBackend {
  public let id: ProviderID = "gemini"
  public let displayName = "Gemini"
  public init() {}

  public func startSession(_ options: AgentSessionOptions) async throws -> any AgentSession {
    throw AgentError.notImplemented(backend: displayName)
  }
}
