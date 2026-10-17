import Foundation
import VoCoderCore

/// What one stream-json line means to the session.
enum ClaudeOutput: Equatable {
  case event(AgentEvent)
  /// The CLI's answer to one of our control requests.
  case controlResponse(requestID: String, result: Result<JSONValue, ControlFailure>)
  /// A `can_use_tool` request; the session keeps the raw suggestions and reports the event.
  case permission(PermissionRequest, suggestions: [JSONValue])
  /// A control request we don't support; it gets an error reply so the CLI doesn't wait.
  case unsupportedControl(requestID: String, subtype: String)
  /// Every `system/init` (one per turn), for the resume id and the version check.
  case turnStarted(AgentSessionInfo)

  struct ControlFailure: Error, Equatable {
    let message: String
  }
}

/// Turns Claude Code's stream-json output (schema: `spikes/claude-code/FINDINGS.md`) into
/// `AgentEvent`s. It keeps the state the protocol needs: which session was announced, tool
/// names by tool-use id, the todo list built from the Task* tools, the streaming text block.
struct ClaudeEventMapper {
  private(set) var announced: AgentSessionInfo?
  private var toolNames: [String: String] = [:]
  private var toolInputs: [String: JSONValue] = [:]
  private var todos: [AgentTodo] = []
  private var tasks: [String: AgentBackgroundTask] = [:]
  // The streaming text block (`--include-partial-messages`).
  private var streamMessageID = ""
  private var streamFilter: SpokenTagFilter?

  /// Forget per-process stream state (a new process after a crash restart).
  mutating func resetStream() {
    streamMessageID = ""
    streamFilter = nil
  }

  mutating func map(line: String) -> [ClaudeOutput] {
    guard !line.allSatisfy(\.isWhitespace) else { return [] }
    guard let message = try? JSONValue(parsing: line), message.object != nil else {
      return [.event(.error(.protocolViolation("not JSON: \(line.prefix(120))")))]
    }
    return map(message)
  }

  mutating func map(_ message: JSONValue) -> [ClaudeOutput] {
    switch message["type"]?.string {
    case "system": system(message)
    case "assistant": assistant(message)
    case "user": user(message)
    case "result": [.event(.turnEnd(turnEnd(message)))]
    case "control_request": controlRequest(message)
    case "control_response": controlResponse(message)
    case "stream_event": streamEvent(message)
    case "rate_limit_event": rateLimit(message)
    default: []
    }
  }

  // MARK: - system

  private mutating func system(_ message: JSONValue) -> [ClaudeOutput] {
    switch message["subtype"]?.string {
    case "init":
      guard let id = message["session_id"]?.string else { return [] }
      let info = AgentSessionInfo(
        id: AgentSessionID(id), model: message["model"]?.string,
        agentVersion: message["claude_code_version"]?.string)
      var outputs: [ClaudeOutput] = [.turnStarted(info)]
      if announced?.id != info.id {
        announced = info
        outputs.append(.event(.sessionStarted(info)))
      }
      return outputs
    case "status":
      guard let status = message["status"]?.string else { return [] }
      return [.event(.status(status == "requesting" ? .requesting : .other(status)))]
    case "thinking_tokens":
      let tokens = message["estimated_tokens"]?.int ?? 0
      return [.event(.status(.thinking(estimatedTokens: tokens)))]
    case "task_started", "task_notification", "task_updated":
      return backgroundTask(message).map { [.event(.backgroundTask($0))] } ?? []
    default:
      return []
    }
  }

  private mutating func backgroundTask(_ message: JSONValue) -> AgentBackgroundTask? {
    guard let id = message["task_id"]?.string else { return nil }
    var task =
      tasks[id]
      ?? AgentBackgroundTask(
        id: id, toolUseID: message["tool_use_id"]?.string, description: "", status: .running)
    if let description = message["description"]?.string ?? message["summary"]?.string {
      task.description = description
    }
    if let backgrounded = message["is_backgrounded"]?.bool { task.isBackgrounded = backgrounded }
    switch message["status"]?.string {
    case "completed": task.status = .completed
    case "failed": task.status = .failed
    case "stopped", "killed": task.status = .stopped
    case "running", "pending": task.status = .running
    default: break
    }
    tasks[id] = task.status == .running ? task : nil
    return task
  }

  // MARK: - assistant / user

  private mutating func assistant(_ message: JSONValue) -> [ClaudeOutput] {
    let messageID = message["message"]?["id"]?.string ?? ""
    let parent = message["parent_tool_use_id"]?.string
    var outputs: [ClaudeOutput] = []
    for block in message["message"]?["content"]?.array ?? [] {
      switch block["type"]?.string {
      case "text":
        let (text, spoken) = SpokenTag.extract(from: block["text"]?.string ?? "")
        if !text.isEmpty {
          outputs.append(
            .event(.text(AgentText(messageID: messageID, text: text, parentToolUseID: parent))))
        }
        if let spoken, parent == nil { outputs.append(.event(.spokenSummary(spoken))) }
      case "tool_use":
        guard let id = block["id"]?.string, let name = block["name"]?.string else { continue }
        let input = block["input"] ?? .object([:])
        toolNames[id] = name
        toolInputs[id] = input
        outputs.append(
          .event(
            .toolUse(AgentToolUse(id: id, name: name, input: input, parentToolUseID: parent))))
      default:
        continue
      }
    }
    return outputs
  }

  private mutating func user(_ message: JSONValue) -> [ClaudeOutput] {
    // Plain text here is the CLI's interrupt marker; the turn's `result` reports it.
    guard let blocks = message["message"]?["content"]?.array else { return [] }
    var outputs: [ClaudeOutput] = []
    for block in blocks where block["type"]?.string == "tool_result" {
      guard let id = block["tool_use_id"]?.string else { continue }
      let isError = block["is_error"]?.bool ?? false
      outputs.append(
        .event(
          .toolResult(
            AgentToolResult(
              toolUseID: id, toolName: toolNames[id], content: Self.text(of: block["content"]),
              isError: isError))))
      if !isError, updateTodos(toolUseID: id, result: message["tool_use_result"]) {
        outputs.append(.event(.todos(todos)))
      }
      toolInputs[id] = nil
    }
    return outputs
  }

  /// Applies a finished `TaskCreate`/`TaskUpdate` call. There's no todo event in headless mode
  /// (no `TodoWrite`); the list comes from these calls.
  private mutating func updateTodos(toolUseID: String, result: JSONValue?) -> Bool {
    guard let input = toolInputs[toolUseID] else { return false }
    switch toolNames[toolUseID] {
    case "TaskCreate":
      guard let task = result?["task"], let id = task["id"]?.string else { return false }
      let subject = task["subject"]?.string ?? input["subject"]?.string ?? ""
      todos.append(AgentTodo(id: id, subject: subject))
      return true
    case "TaskUpdate":
      guard let id = input["taskId"]?.string ?? result?["taskId"]?.string,
        let index = todos.firstIndex(where: { $0.id == id })
      else { return false }
      if let subject = input["subject"]?.string { todos[index].subject = subject }
      switch input["status"]?.string {
      case "pending": todos[index].status = .pending
      case "in_progress": todos[index].status = .inProgress
      case "completed": todos[index].status = .completed
      case "deleted": todos.remove(at: index)
      default: break
      }
      return true
    default:
      return false
    }
  }

  // MARK: - result

  private func turnEnd(_ message: JSONValue) -> AgentTurnEnd {
    let outcome: AgentTurnEnd.Outcome
    if message["subtype"]?.string == "success" && message["is_error"]?.bool != true {
      outcome = .completed
    } else if message["terminal_reason"]?.string?.hasPrefix("aborted") == true {
      outcome = .interrupted
    } else {
      let errors = (message["errors"]?.array ?? []).compactMap(\.string)
      outcome = .failed(
        errors.isEmpty
          ? message["result"]?.string ?? message["subtype"]?.string ?? "error"
          : errors.joined(separator: "; "))
    }
    return AgentTurnEnd(
      outcome: outcome,
      text: message["result"]?.string.map { SpokenTag.extract(from: $0).text },
      duration: message["duration_ms"]?.int.map { .milliseconds($0) },
      costUSD: message["total_cost_usd"]?.double)
  }

  // MARK: - control protocol

  private func controlRequest(_ message: JSONValue) -> [ClaudeOutput] {
    guard let requestID = message["request_id"]?.string, let request = message["request"]
    else { return [] }
    let subtype = request["subtype"]?.string ?? "?"
    guard subtype == "can_use_tool", let tool = request["tool_name"]?.string else {
      return [.unsupportedControl(requestID: requestID, subtype: subtype)]
    }
    let suggestions = request["permission_suggestions"]?.array ?? []
    let permission = PermissionRequest(
      id: requestID, toolName: tool, displayName: request["display_name"]?.string,
      input: request["input"] ?? .object([:]), description: request["description"]?.string,
      toolUseID: request["tool_use_id"]?.string, blockedPath: request["blocked_path"]?.string,
      offersSessionRule: !suggestions.isEmpty)
    return [.permission(permission, suggestions: suggestions)]
  }

  private func controlResponse(_ message: JSONValue) -> [ClaudeOutput] {
    guard let response = message["response"], let id = response["request_id"]?.string else {
      return []
    }
    if response["subtype"]?.string == "success" {
      return [.controlResponse(requestID: id, result: .success(response["response"] ?? .null))]
    }
    let error = response["error"]?.string ?? "control request failed"
    return [.controlResponse(requestID: id, result: .failure(.init(message: error)))]
  }

  // MARK: - streaming and quota

  private mutating func streamEvent(_ message: JSONValue) -> [ClaudeOutput] {
    guard let event = message["event"] else { return [] }
    switch event["type"]?.string {
    case "message_start":
      streamMessageID = event["message"]?["id"]?.string ?? ""
    case "content_block_start":
      streamFilter = event["content_block"]?["type"]?.string == "text" ? SpokenTagFilter() : nil
    case "content_block_delta":
      guard event["delta"]?["type"]?.string == "text_delta",
        let chunk = event["delta"]?["text"]?.string, streamFilter != nil
      else { return [] }
      let visible = streamFilter!.feed(chunk)
      if !visible.isEmpty { return [delta(visible)] }
    case "content_block_stop":
      let rest = streamFilter?.finish() ?? ""
      streamFilter = nil
      if !rest.isEmpty { return [delta(rest)] }
    default:
      break
    }
    return []
  }

  private func delta(_ text: String) -> ClaudeOutput {
    .event(.textDelta(AgentTextDelta(messageID: streamMessageID, text: text)))
  }

  private func rateLimit(_ message: JSONValue) -> [ClaudeOutput] {
    guard let info = message["rate_limit_info"] else { return [] }
    let windows = (info["unifiedWindows"]?.object ?? [:]).sorted { $0.key < $1.key }.compactMap {
      name, window -> AgentUsage.Window? in
      guard let utilization = window["utilization"]?.double else { return nil }
      return AgentUsage.Window(
        name: name, utilization: utilization,
        resetsAt: window["resetsAt"]?.double.map { Date(timeIntervalSince1970: $0) })
    }
    return [.event(.usage(AgentUsage(status: info["status"]?.string ?? "", windows: windows)))]
  }

  /// A tool result's content: a string, or text blocks.
  static func text(of content: JSONValue?) -> String {
    switch content {
    case .string(let text): text
    case .array(let blocks): blocks.compactMap { $0["text"]?.string }.joined(separator: "\n")
    default: ""
    }
  }
}
