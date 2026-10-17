import Foundation
import VoCoderCore

/// How to start one `claude` process: the session rebuilds it (with `--resume`) on a crash
/// restart.
public struct ClaudeLaunch: Sendable, Equatable {
  public var executable: URL
  public var arguments: [String]
  public var environment: [String: String]
  public var directory: URL

  public init(
    executable: URL, arguments: [String], environment: [String: String], directory: URL
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.directory = directory
  }

  /// The stream-json host-protocol invocation (ADR 0002).
  public static func arguments(
    config: ClaudeCodeConfig, model: String?, resume: AgentSessionID?
  ) -> [String] {
    var arguments = [
      "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
      "--include-partial-messages", "--permission-prompt-tool", "stdio",
      "--permission-mode", "manual", "--tools", tools.joined(separator: ","),
      "--append-system-prompt", spokenInstruction,
    ]
    if config.mcpServers == .none { arguments.append("--strict-mcp-config") }
    if let model = model ?? config.model { arguments += ["--model", model] }
    if let resume { arguments += ["--resume", resume.rawValue] }
    return arguments
  }

  /// Passed explicitly: the headless default set lacks the Task* tools that carry todos.
  public static let tools = [
    "Bash", "Read", "Write", "Edit", "Glob", "Grep", "WebFetch", "WebSearch",
    "TaskCreate", "TaskUpdate", "TaskList", "TaskGet",
  ]

  /// Asks for the `<spoken>` summary (45/45 compliance in the P0-04 spike).
  public static let spokenInstruction = """
    You are running inside VoCoder, a voice-first terminal workspace. The user may be listening \
    rather than reading. End every reply with a short summary for text-to-speech inside \
    <spoken>...</spoken> tags: one or two plain sentences, at most 40 words, no markdown, no code, \
    no file paths or symbols. Put it last, after any other content.
    """

  /// `environment` without what makes `claude` act as a nested session of the Claude Code that
  /// may have launched VoCoder (`CLAUDECODE`, `CLAUDE_CODE_*`, `CLAUDE_PID`, `AI_AGENT`; ADR
  /// 0002). The user's own provider settings among `CLAUDE_CODE_*` are kept (ADR 0010).
  public static func sanitized(_ environment: [String: String]) -> [String: String] {
    environment.filter { key, _ in
      let parent = parentSessionKeys.contains(key) || key.hasPrefix("CLAUDE_CODE_")
      return !parent || userSettings.contains(key)
    }
  }

  static let parentSessionKeys: Set<String> = ["CLAUDECODE", "CLAUDE_PID", "AI_AGENT"]

  /// `CLAUDE_CODE_*` variables that configure the user's account, not a parent session.
  static let userSettings: Set<String> = [
    "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY",
    "CLAUDE_CODE_OAUTH_TOKEN",
  ]
}
