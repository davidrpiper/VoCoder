import Foundation

/// Everything a session reports, in order (DESIGN §4.4).
public enum AgentEvent: Sendable, Equatable {
  /// The first turn started (once per session; a crash restart that resumes doesn't repeat it
  /// unless the id changed).
  case sessionStarted(AgentSessionInfo)
  case status(AgentStatus)
  /// One complete text block. With streaming on it follows the block's `textDelta`s and is
  /// the authoritative text. `<spoken>` is already removed (see `spokenSummary`).
  case text(AgentText)
  /// A streamed piece of the text block being written (`<spoken>` filtered out).
  case textDelta(AgentTextDelta)
  case toolUse(AgentToolUse)
  case toolResult(AgentToolResult)
  /// The agent's whole todo list after a change.
  case todos([AgentTodo])
  case permissionRequest(PermissionRequest)
  case backgroundTask(AgentBackgroundTask)
  /// Plan quota (rate-limit windows).
  case usage(AgentUsage)
  /// The short text-to-speech summary of a reply (from its `<spoken>` tag).
  case spokenSummary(String)
  case turnEnd(AgentTurnEnd)
  /// Something went wrong but the session goes on (or is restarting).
  case error(AgentError)
  /// Last event: the session is over.
  case ended(AgentEndReason)
}

public struct AgentSessionInfo: Sendable, Equatable {
  public var id: AgentSessionID
  public var model: String?
  /// The agent's own version (e.g. Claude Code's CLI version).
  public var agentVersion: String?

  public init(id: AgentSessionID, model: String? = nil, agentVersion: String? = nil) {
    self.id = id
    self.model = model
    self.agentVersion = agentVersion
  }
}

public enum AgentStatus: Sendable, Equatable {
  /// Waiting for the model.
  case requesting
  case thinking(estimatedTokens: Int)
  case other(String)
}

public struct AgentText: Sendable, Equatable {
  /// Blocks of one model message share it.
  public var messageID: String
  public var text: String
  /// Set when a sub-agent wrote it.
  public var parentToolUseID: String?

  public init(messageID: String, text: String, parentToolUseID: String? = nil) {
    self.messageID = messageID
    self.text = text
    self.parentToolUseID = parentToolUseID
  }
}

public struct AgentTextDelta: Sendable, Equatable {
  public var messageID: String
  public var text: String

  public init(messageID: String, text: String) {
    self.messageID = messageID
    self.text = text
  }
}

public struct AgentToolUse: Sendable, Equatable {
  public var id: String
  public var name: String
  public var input: JSONValue
  public var parentToolUseID: String?

  public init(id: String, name: String, input: JSONValue, parentToolUseID: String? = nil) {
    self.id = id
    self.name = name
    self.input = input
    self.parentToolUseID = parentToolUseID
  }
}

public struct AgentToolResult: Sendable, Equatable {
  public var toolUseID: String
  /// The tool's name, when its `toolUse` was seen.
  public var toolName: String?
  /// What the model sees (for errors: the reason, e.g. a denial message).
  public var content: String
  public var isError: Bool

  public init(toolUseID: String, toolName: String?, content: String, isError: Bool = false) {
    self.toolUseID = toolUseID
    self.toolName = toolName
    self.content = content
    self.isError = isError
  }
}

public struct AgentTodo: Sendable, Equatable, Identifiable {
  public enum Status: String, Sendable, Equatable {
    case pending, inProgress, completed
  }

  public var id: String
  public var subject: String
  public var status: Status

  public init(id: String, subject: String, status: Status = .pending) {
    self.id = id
    self.subject = subject
    self.status = status
  }
}

/// The agent wants to run a tool and needs a yes or no.
public struct PermissionRequest: Sendable, Equatable, Identifiable {
  public var id: String
  public var toolName: String
  /// The tool's user-facing name.
  public var displayName: String
  public var input: JSONValue
  /// What the call does, in the agent's words.
  public var description: String?
  public var toolUseID: String?
  /// The file or directory that made this need approval.
  public var blockedPath: String?
  /// `allowForSession` adds a rule (otherwise it acts as `allowOnce`).
  public var offersSessionRule: Bool

  public init(
    id: String, toolName: String, displayName: String? = nil, input: JSONValue,
    description: String? = nil, toolUseID: String? = nil, blockedPath: String? = nil,
    offersSessionRule: Bool = false
  ) {
    self.id = id
    self.toolName = toolName
    self.displayName = displayName ?? toolName
    self.input = input
    self.description = description
    self.toolUseID = toolUseID
    self.blockedPath = blockedPath
    self.offersSessionRule = offersSessionRule
  }
}

public struct AgentBackgroundTask: Sendable, Equatable {
  public enum Status: String, Sendable, Equatable {
    case running, completed, failed, stopped
  }

  public var id: String
  public var toolUseID: String?
  public var description: String
  public var status: Status
  /// Running detached from the turn (it may start a turn by itself when it finishes).
  public var isBackgrounded: Bool

  public init(
    id: String, toolUseID: String? = nil, description: String, status: Status,
    isBackgrounded: Bool = false
  ) {
    self.id = id
    self.toolUseID = toolUseID
    self.description = description
    self.status = status
    self.isBackgrounded = isBackgrounded
  }
}

public struct AgentUsage: Sendable, Equatable {
  public struct Window: Sendable, Equatable {
    /// `five_hour`, `seven_day`, …
    public var name: String
    /// 0…1.
    public var utilization: Double
    public var resetsAt: Date?

    public init(name: String, utilization: Double, resetsAt: Date? = nil) {
      self.name = name
      self.utilization = utilization
      self.resetsAt = resetsAt
    }
  }

  /// `allowed`, `allowed_warning`, `rejected`, …
  public var status: String
  public var windows: [Window]

  public init(status: String, windows: [Window]) {
    self.status = status
    self.windows = windows
  }
}

public struct AgentTurnEnd: Sendable, Equatable {
  public enum Outcome: Sendable, Equatable {
    case completed
    case interrupted
    case failed(String)
  }

  public var outcome: Outcome
  /// The reply's final text (without `<spoken>`).
  public var text: String?
  public var duration: Duration?
  public var costUSD: Double?

  public init(
    outcome: Outcome, text: String? = nil, duration: Duration? = nil, costUSD: Double? = nil
  ) {
    self.outcome = outcome
    self.text = text
    self.duration = duration
    self.costUSD = costUSD
  }
}

public enum AgentEndReason: Sendable, Equatable {
  /// `close()` was called.
  case closed
  /// The agent exited and wasn't (or couldn't be) restarted.
  case exited(status: Int32)
}
