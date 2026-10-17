import Foundation

// Coding agents (DESIGN §4.4, ADR 0002, ADR 0010). Vendor-neutral: Claude Code is one adapter,
// Codex and Gemini are stubs. Each repo tab owns one session.

/// A coding agent that can run sessions in a repo (Claude Code; Codex and Gemini stubs).
public protocol AgentBackend: Provider {
  /// Shown and spoken ("Claude Code").
  var displayName: String { get }
  /// Starts the agent in `options.repo` and returns once it accepts prompts. Throws
  /// `AgentError` when the agent is missing, too old, or fails to start (also an unknown
  /// resume id).
  func startSession(_ options: AgentSessionOptions) async throws -> any AgentSession
}

/// A running agent conversation.
///
/// `events` is one continuous stream for the session's whole life: the agent may start turns
/// on its own (a background task finished), so it's not request/response. It ends after
/// `.ended`. Prompts sent while a turn runs are queued by the agent.
public protocol AgentSession: AnyObject, Sendable {
  var events: AsyncStream<AgentEvent> { get }
  /// Sends a user turn. Throws `AgentError.notRunning` after the session ended.
  func send(_ prompt: String) async throws
  /// Answers a `.permissionRequest`. Throws `AgentError.unknownRequest` for a request that
  /// isn't pending (already answered, or from an earlier process).
  func respond(to request: PermissionRequest, _ decision: PermissionDecision) async throws
  /// Stops the running turn (it ends with `.interrupted`); harmless when idle.
  func interrupt() async
  /// Stops the agent. `events` ends with `.ended(.closed)`. Idempotent.
  func close() async
}

/// The agent's own conversation id, used to resume it later.
public struct AgentSessionID: RawRepresentable, Hashable, Sendable, Codable,
  CustomStringConvertible, ExpressibleByStringLiteral
{
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }
  public var description: String { rawValue }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public struct AgentSessionOptions: Sendable, Equatable {
  /// The working directory (a repo root).
  public var repo: URL
  /// Continue this conversation instead of starting a new one.
  public var resume: AgentSessionID?
  /// A backend-specific model name or alias; nil uses the backend's configured default.
  public var model: String?

  public init(repo: URL, resume: AgentSessionID? = nil, model: String? = nil) {
    self.repo = repo
    self.resume = resume
    self.model = model
  }
}

/// How the user answers a permission request (ADR 0002).
public enum PermissionDecision: Sendable, Equatable {
  case allowOnce
  /// Allow, running the tool with this input instead of the requested one.
  case allowEdited(JSONValue)
  /// Allow, and stop asking for similar calls until the session ends (needs
  /// `PermissionRequest.offersSessionRule`; otherwise the same as `allowOnce`).
  case allowForSession
  /// Allow, and remember it in the repo's agent settings. Only on an explicit user choice.
  case allowAlways
  /// Refuse; the agent sees `message`.
  case deny(message: String)
}

public enum AgentError: Error, Sendable, Equatable, CustomStringConvertible {
  /// A stub backend.
  case notImplemented(backend: String)
  case executableNotFound(String)
  case unsupportedVersion(found: String, minimum: String)
  /// The agent process didn't start or exited during startup.
  case launchFailed(String)
  /// The session has ended.
  case notRunning
  case unknownRequest(String)
  /// The agent sent something we couldn't understand (logged; the session continues).
  case protocolViolation(String)
  /// The agent process exited unexpectedly. `restarting` is the attempt about to be made.
  case crashed(status: Int32, restarting: Int?)

  public var description: String {
    switch self {
    case .notImplemented(let backend): "\(backend) isn't supported yet"
    case .executableNotFound(let name): "\(name) wasn't found"
    case .unsupportedVersion(let found, let minimum):
      "agent version \(found) is older than \(minimum)"
    case .launchFailed(let message): "the agent failed to start: \(message)"
    case .notRunning: "the agent isn't running"
    case .unknownRequest(let id): "no pending permission request \(id)"
    case .protocolViolation(let message): "unexpected agent output: \(message)"
    case .crashed(let status, let restarting?):
      "the agent exited (status \(status)); restarting (attempt \(restarting))"
    case .crashed(let status, nil): "the agent exited (status \(status))"
    }
  }
}
