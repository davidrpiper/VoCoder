// The repo tab's conversation (DESIGN §3.2): agent events folded into entries the view draws.
// A pure value: `apply(_:)` is the whole state machine, so tests feed it events directly.
import Foundation
import VoCoderCore

struct Conversation: Equatable {
  /// One thing in the transcript.
  enum Entry: Equatable, Identifiable {
    case prompt(id: Int, text: String)
    case message(Message)
    case tool(ToolCall)
    case notice(id: Int, Notice)
    case turnEnd(id: Int, AgentTurnEnd)

    var id: Int {
      switch self {
      case .prompt(let id, _), .notice(let id, _), .turnEnd(let id, _): id
      case .message(let message): message.id
      case .tool(let tool): tool.id
      }
    }
  }

  /// One text block of an agent message. The parsed document is cached; a block still
  /// streaming is re-parsed as deltas arrive (ADR 0012), and the final text replaces it.
  struct Message: Equatable {
    let id: Int
    let messageID: String
    var text: String
    var document: MarkdownDocument
    var isStreaming: Bool
    /// Written by a sub-agent (indented under its tool call).
    var isNested: Bool
  }

  struct ToolCall: Equatable {
    let id: Int
    let use: AgentToolUse
    var result: AgentToolResult?
    /// A permission request for this call is waiting.
    var awaitingApproval = false
    var denied = false

  }

  struct Notice: Equatable {
    enum Kind: Equatable { case info, error }
    var kind: Kind
    var text: String
  }

  private(set) var entries: [Entry] = []
  private(set) var todos: [AgentTodo] = []
  /// Unanswered permission requests, oldest first.
  private(set) var approvals: [PermissionRequest] = []
  private(set) var session: AgentSessionInfo?
  /// A turn is running (from a sent prompt or the agent's own start until `turnEnd`).
  private(set) var isWorking = false
  /// The newest spoken summary (read aloud later, P2-08).
  private(set) var lastSpoken: String?
  /// The agent's process crashed or failed a turn since the last prompt.
  private(set) var hasError = false
  private(set) var ended: AgentEndReason?
  private var nextID = 1

  var pendingApproval: PermissionRequest? { approvals.first }

  /// Tool calls in transcript order (for moving between them).
  var toolIDs: [Int] {
    entries.compactMap { if case .tool(let tool) = $0 { tool.id } else { nil } }
  }

  mutating func addPrompt(_ text: String) {
    append(.prompt(id: takeID(), text: text))
    isWorking = true
    hasError = false
  }

  mutating func addNotice(_ text: String, kind: Notice.Kind = .info) {
    append(.notice(id: takeID(), Notice(kind: kind, text: text)))
    if kind == .error { hasError = true }
  }

  /// Removes `request` from the queue once answered; a denial marks its tool call.
  mutating func answered(_ request: PermissionRequest, denied: Bool) {
    approvals.removeAll { $0.id == request.id }
    updateTool(useID: request.toolUseID) { tool in
      tool.awaitingApproval = false
      tool.denied = denied
    }
  }

  mutating func apply(_ event: AgentEvent) {
    switch event {
    case .sessionStarted(let info):
      session = info
    case .status:
      isWorking = true
    case .textDelta(let delta):
      isWorking = true
      if case .message(var message) = entries.last, message.isStreaming,
        message.messageID == delta.messageID
      {
        message.text += delta.text
        message.document = MarkdownDocument(parsing: message.text)
        entries[entries.count - 1] = .message(message)
      } else {
        appendMessage(messageID: delta.messageID, text: delta.text, streaming: true, nested: false)
      }
    case .text(let text):
      let nested = text.parentToolUseID != nil
      if let index = entries.lastIndex(where: {
        if case .message(let message) = $0 {
          message.isStreaming && message.messageID == text.messageID
        } else {
          false
        }
      }), case .message(var message) = entries[index] {
        message.text = text.text
        message.document = MarkdownDocument(parsing: text.text)
        message.isStreaming = false
        message.isNested = nested
        entries[index] = .message(message)
      } else if !text.text.isEmpty {
        appendMessage(messageID: text.messageID, text: text.text, streaming: false, nested: nested)
      }
    case .toolUse(let use):
      isWorking = true
      finishStreaming()
      append(.tool(ToolCall(id: takeID(), use: use)))
    case .toolResult(let result):
      updateTool(useID: result.toolUseID) { tool in
        tool.result = result
        tool.awaitingApproval = false
      }
    case .todos(let list):
      todos = list
    case .permissionRequest(let request):
      approvals.append(request)
      updateTool(useID: request.toolUseID) { $0.awaitingApproval = true }
    case .backgroundTask(let task):
      switch task.status {
      case .running: break
      case .completed: addNotice("Background task finished: \(task.description)")
      case .failed: addNotice("Background task failed: \(task.description)", kind: .error)
      case .stopped: addNotice("Background task stopped: \(task.description)")
      }
    case .usage:
      break
    case .spokenSummary(let text):
      lastSpoken = text
    case .turnEnd(let end):
      finishStreaming()
      // A request left after its turn can't be answered any more (ADR 0010).
      for request in approvals { answered(request, denied: false) }
      isWorking = false
      if case .failed = end.outcome { hasError = true }
      append(.turnEnd(id: takeID(), end))
    case .error(let error):
      addNotice(
        error.description.prefix(1).uppercased() + error.description.dropFirst(),
        kind: .error)
    case .ended(let reason):
      finishStreaming()
      approvals.removeAll()
      isWorking = false
      ended = reason
      switch reason {
      case .closed: break
      case .exited(let status):
        addNotice(
          "The agent stopped (exit status \(status)). Send a prompt to restart it.",
          kind: .error)
      }
    }
  }

  // MARK: Helpers

  private mutating func takeID() -> Int {
    defer { nextID += 1 }
    return nextID
  }

  private mutating func append(_ entry: Entry) { entries.append(entry) }

  private mutating func appendMessage(
    messageID: String, text: String, streaming: Bool, nested: Bool
  ) {
    append(
      .message(
        Message(
          id: takeID(), messageID: messageID, text: text,
          document: MarkdownDocument(parsing: text), isStreaming: streaming, isNested: nested)))
  }

  private mutating func finishStreaming() {
    for index in entries.indices {
      if case .message(var message) = entries[index], message.isStreaming {
        message.isStreaming = false
        entries[index] = .message(message)
      }
    }
  }

  private mutating func updateTool(useID: String?, _ change: (inout ToolCall) -> Void) {
    guard let useID else { return }
    guard
      let index = entries.lastIndex(where: {
        if case .tool(let tool) = $0 { tool.use.id == useID } else { false }
      }), case .tool(var tool) = entries[index]
    else { return }
    change(&tool)
    entries[index] = .tool(tool)
  }
}
