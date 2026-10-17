import Foundation

/// How permission prompts reach us.
enum PermissionChannel: Sendable {
  /// `--permission-prompt-tool stdio`: `can_use_tool` control requests on the stream-json pipe.
  case host
  /// `--permission-prompt-tool mcp__<server>__<tool>` backed by our stdio MCP server.
  case mcp(configPath: String, tool: String)
  /// Nobody answers; anything that would prompt is denied.
  case none
}

struct ClaudeOptions: Sendable {
  var cwd: URL
  var model = "haiku"
  var tools = "Bash,Write,Read,Edit"
  var permissionMode = "manual"
  var permission = PermissionChannel.host
  var resume: String?
  var appendSystemPrompt: String?
  var partialMessages = false
  var extraArgs: [String] = []

  var arguments: [String] {
    var a = [
      "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
      "--model", model, "--tools", tools, "--permission-mode", permissionMode,
    ]
    switch permission {
    case .host: a += ["--permission-prompt-tool", "stdio"]
    case .mcp(let config, let tool):
      a += ["--mcp-config", config, "--strict-mcp-config", "--permission-prompt-tool", tool]
    case .none: a += ["--permission-prompts", "none"]
    }
    if case .mcp = permission {} else { a += ["--strict-mcp-config"] }
    if let resume { a += ["--resume", resume] }
    if let appendSystemPrompt { a += ["--append-system-prompt", appendSystemPrompt] }
    if partialMessages { a += ["--include-partial-messages"] }
    return a + extraArgs
  }
}

/// Raw transcript writer: what we sent and what we received, verbatim, one NDJSON file each.
final class Transcript: @unchecked Sendable {
  private let lock = NSLock()
  private var out: [String] = []
  private var input: [String] = []
  let name: String
  init(name: String) { self.name = name }

  private(set) var stderrText = ""
  func received(_ line: String) { lock.withLock { out.append(line) } }
  func stderr(_ text: String) { lock.withLock { stderrText += text } }
  func sent(_ line: String) { lock.withLock { input.append(line) } }

  /// Saves `<name>.out.ndjson` / `<name>.in.ndjson` with machine-specific paths scrubbed.
  func save(to dir: URL, scrub: [(String, String)]) throws {
    let (o, i) = lock.withLock { (out, input) }
    func clean(_ lines: [String]) -> String { scrubText(lines.joined(separator: "\n") + "\n", scrub) }
    try clean(o).write(to: dir.appending(path: "\(name).out.ndjson"), atomically: true, encoding: .utf8)
    try clean(i).write(to: dir.appending(path: "\(name).in.ndjson"), atomically: true, encoding: .utf8)
  }
}

/// Removes machine/account specifics: given path pairs (also in Claude Code's dash-mangled
/// project-dir form), account email/organization values, and the login name.
func scrubText(_ text: String, _ pairs: [(String, String)]) -> String {
  var s = text
  for (from, to) in pairs {
    s = s.replacingOccurrences(of: from, with: to)
    s = s.replacingOccurrences(of: from.replacingOccurrences(of: "/", with: "-"), with: to.replacingOccurrences(of: "/", with: "-"))
  }
  s = s.replacing(/"(email|organization)":"[^"]*"/) { m in "\"\(m.1)\":\"REDACTED\"" }
  return s.replacingOccurrences(of: NSUserName(), with: "user")
}

enum ClaudeError: Error { case notRunning, exited(Int32) }

/// One `claude -p` stream-json process. Events (everything except responses to our own control
/// requests) arrive on `events`; control responses resolve the matching `control(...)` call.
actor ClaudeProcess {
  nonisolated let events: AsyncStream<JSON>
  private let eventSink: AsyncStream<JSON>.Continuation
  private let process = Process()
  private let stdin = Pipe()
  private let stdout = Pipe()
  private let stderr = Pipe()
  private var pending: [String: CheckedContinuation<JSON, Never>] = [:]
  private var nextRequest = 1
  nonisolated let transcript: Transcript
  nonisolated let started = ContinuousClock.now

  init(_ options: ClaudeOptions, transcript: Transcript) {
    self.transcript = transcript
    (events, eventSink) = AsyncStream.makeStream(of: JSON.self)
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = ["claude"] + options.arguments
    process.currentDirectoryURL = options.cwd
    // When launched from inside a Claude Code session these leak in and make the child behave as
    // a nested session; VoCoder must strip them too.
    process.environment = ProcessInfo.processInfo.environment.filter { key, _ in
      !(key.hasPrefix("CLAUDE") || key == "AI_AGENT")
    }
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
  }

  func start() throws {
    stderr.fileHandleForReading.readabilityHandler = { [transcript] h in
      transcript.stderr(String(decoding: h.availableData, as: UTF8.self))
    }
    try process.run()
    let handle = stdout.fileHandleForReading
    Task.detached { [weak self, transcript, eventSink] in
      do {
        for try await line in handle.bytes.lines {
          transcript.received(line)
          if trace { log("<< " + line.prefix(300)) }
          guard let msg = try? JSON.parse(line) else {
            log("unparseable stdout line: \(line.prefix(200))")
            continue
          }
          if msg["type"]?.string == "control_response",
            let id = msg["response"]?["request_id"]?.string,
            await self?.resolve(id, msg["response"]!) == true
          {
            continue
          }
          eventSink.yield(msg)
        }
      } catch {
        log("stdout read error: \(error)")
      }
      eventSink.finish()
      await self?.failPending()
    }
  }

  /// stdout closed: nobody will answer outstanding control requests.
  private func failPending() {
    for (_, c) in pending { c.resume(returning: ["subtype": "error", "error": "process exited"]) }
    pending.removeAll()
  }

  private func resolve(_ id: String, _ response: JSON) -> Bool {
    guard let c = pending.removeValue(forKey: id) else { return false }
    c.resume(returning: response)
    return true
  }

  private func write(_ msg: JSON) throws {
    guard process.isRunning else { throw ClaudeError.notRunning }
    let line = msg.line
    transcript.sent(line)
    if trace { log(">> " + line.prefix(300)) }
    try stdin.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
  }

  /// Sends a user turn. Turns sent while one is running are queued by Claude Code.
  func send(_ prompt: String) throws {
    try write(["type": "user", "message": ["role": "user", "content": .string(prompt)]])
  }

  /// Sends a control request (e.g. `initialize`, `interrupt`) and waits for its response.
  func control(_ subtype: String, _ extra: [String: JSON] = [:]) async throws -> JSON {
    let id = "vc-\(nextRequest)"
    nextRequest += 1
    var request = extra
    request["subtype"] = .string(subtype)
    let msg: JSON = ["type": "control_request", "request_id": .string(id), "request": .object(request)]
    return await withCheckedContinuation { c in
      pending[id] = c
      do { try write(msg) } catch {
        pending.removeValue(forKey: id)
        c.resume(returning: ["subtype": "error", "error": .string("\(error)")])
      }
    }
  }

  /// Answers a `can_use_tool` control request from Claude Code.
  func respond(to requestID: String, _ response: JSON) throws {
    try write([
      "type": "control_response",
      "response": ["subtype": "success", "request_id": .string(requestID), "response": response],
    ])
  }

  func closeInput() throws { try stdin.fileHandleForWriting.close() }

  func signal(_ sig: Int32) { kill(process.processIdentifier, sig) }

  func waitForExit(timeout: Duration = .seconds(30)) async -> Int32? {
    let deadline = ContinuousClock.now + timeout
    while process.isRunning {
      if ContinuousClock.now > deadline { return nil }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return process.terminationStatus
  }

  func terminate() { if process.isRunning { process.terminate() } }
}

let trace = ProcessInfo.processInfo.environment["CC_TRACE"] != nil

func log(_ s: String) {
  FileHandle.standardError.write(Data((s + "\n").utf8))
}

extension Duration {
  var ms: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
