import Foundation

/// A permission policy: given the `can_use_tool` request (or MCP tool args), returns the decision
/// object (`{"behavior":"allow","updatedInput":…}` / `{"behavior":"deny","message":…}`).
typealias PermissionPolicy = @Sendable (JSON) -> JSON

struct PermissionRecord: Sendable {
  var request: JSON
  var decision: JSON
  var receivedAt: Duration
}

struct TurnResult {
  var text: String
  var result: JSON
  var events: [JSON]
  var sentAt: Duration
  var firstTextAt: Duration?
  var resultAt: Duration
  var latencyMs: Int { (resultAt - sentAt).ms }
  var firstTextMs: Int? { firstTextAt.map { ($0 - sentAt).ms } }
}

/// Consumes one process's event stream turn by turn, answering host permission prompts.
@MainActor
final class Session {
  let proc: ClaudeProcess
  private var iterator: AsyncStream<JSON>.Iterator
  var sessionID: String?
  var policy: PermissionPolicy = { allow($0) }
  var permissions: [PermissionRecord] = []
  var toolResultTimes: [String: Duration] = [:]
  /// Called for every event while collecting (e.g. to trigger an interrupt).
  var onEvent: ((JSON) -> Void)?

  init(_ options: ClaudeOptions, name: String) {
    proc = ClaudeProcess(options, transcript: Transcript(name: name))
    iterator = proc.events.makeAsyncIterator()
  }

  var now: Duration { ContinuousClock.now - proc.started }

  func start(initialize: Bool = true) async throws -> JSON? {
    try await proc.start()
    return initialize ? try await proc.control("initialize") : nil
  }

  func turn(_ prompt: String) async throws -> TurnResult {
    let sent = now
    try await proc.send(prompt)
    return try await collect(sentAt: sent)
  }

  /// Reads events until the next `result`.
  func collect(sentAt: Duration) async throws -> TurnResult {
    var events: [JSON] = []
    var text = ""
    var firstText: Duration?
    // A mutating async call on a stored (actor-isolated) iterator is rejected; AsyncStream's
    // iterator is reference-backed, so a local copy advances the same stream.
    var it = iterator
    defer { iterator = it }
    while let e = await it.next(isolation: #isolation) {
      events.append(e)
      onEvent?(e)
      switch e["type"]?.string {
      case "system" where e["subtype"]?.string == "init":
        sessionID = e["session_id"]?.string
      case "control_request" where e["request"]?["subtype"]?.string == "can_use_tool":
        let req = e["request"]!
        let decision = policy(req)
        permissions.append(PermissionRecord(request: req, decision: decision, receivedAt: now))
        try await proc.respond(to: e["request_id"]!.string!, decision)
      case "user":
        for block in e["message"]?["content"]?.array ?? [] where block["type"]?.string == "tool_result" {
          if let id = block["tool_use_id"]?.string { toolResultTimes[id] = now }
        }
      case "assistant":
        for block in e["message"]?["content"]?.array ?? [] where block["type"]?.string == "text" {
          if firstText == nil { firstText = now }
          text += block["text"]?.string ?? ""
        }
      case "result":
        return TurnResult(text: text, result: e, events: events, sentAt: sentAt, firstTextAt: firstText, resultAt: now)
      default: break
      }
    }
    throw ClaudeError.exited(await proc.waitForExit(timeout: .seconds(5)) ?? -1)
  }

  /// Closes stdin, waits for exit and saves the transcript as fixtures.
  func finish(fixtures: URL, scrub: [(String, String)]) async -> Int32? {
    try? await proc.closeInput()
    let status = await proc.waitForExit()
    await proc.terminate()
    try? proc.transcript.save(to: fixtures, scrub: scrub)
    return status
  }
}

func allow(_ req: JSON) -> JSON { ["behavior": "allow", "updatedInput": req["input"] ?? [:]] }
func deny(_ message: String) -> JSON { ["behavior": "deny", "message": .string(message)] }
