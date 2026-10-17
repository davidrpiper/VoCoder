import ClaudeCodeModule
import Foundation
import Synchronization
import Testing
import VoCoderCore

/// A recorded Claude Code transcript (`Fixtures/claude-code/<name>.{out,in}.ndjson`).
struct ClaudeFixture {
  let name: String
  let output: [String]
  let input: [JSONValue]

  init(_ name: String) throws {
    self.name = name
    func lines(_ suffix: String) throws -> [String] {
      let url = try #require(
        Bundle.module.url(
          forResource: "\(name).\(suffix)", withExtension: "ndjson",
          subdirectory: "Fixtures/claude-code"))
      return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }
    output = try lines("out")
    input = try lines("in").map { try JSONValue(parsing: $0) }
  }

  /// The user prompts the spike sent, in order.
  var prompts: [String] {
    input.filter { $0["type"]?.string == "user" }.compactMap { $0["message"]?["content"]?.string }
  }

  /// The permission answers the spike sent, by request id.
  var permissionAnswers: [JSONValue] {
    input.filter { $0["type"]?.string == "control_response" }
  }
}

/// Plays a fixture's stdout as if from `claude`, holding each line back until what produced
/// it has been written: the n-th `system/init` waits for the n-th user message, a
/// `control_response` for our matching request, and anything after a `can_use_tool` for its
/// answer. Control requests the fixture never answers (an idle interrupt) get a success reply.
final class ReplayTransport: ClaudeTransport {
  let lines: AsyncStream<String>
  private let continuation: AsyncStream<String>.Continuation
  private let state = Mutex(State())
  let recentErrorOutput: String

  private struct State {
    var written: [JSONValue] = []
    var inputClosed = false
    var exitStatus: Int32?
    var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    var stall: String?
  }

  /// `exitAfterScript`: exit with this status after the last line (a crash or a startup
  /// failure); nil waits for stdin to close, like the CLI.
  init(
    _ fixture: ClaudeFixture, exitAfterScript: Int32? = nil, stderr: String = "",
    gateTimeout: Duration = .seconds(5)
  ) {
    (lines, continuation) = AsyncStream.makeStream()
    recentErrorOutput = stderr
    script = fixture.output
    self.exitAfterScript = exitAfterScript
    self.gateTimeout = gateTimeout
  }

  private let script: [String]
  private let exitAfterScript: Int32?
  private let gateTimeout: Duration

  /// Starts playback (at launch, so gate timeouts don't run while the transport waits).
  func start() {
    Task { [self] in await play(script, exitAfterScript: exitAfterScript, timeout: gateTimeout) }
  }

  /// Every message written to stdin.
  var written: [JSONValue] { state.withLock { $0.written } }
  /// Why playback stopped early, if it did.
  var stall: String? { state.withLock { $0.stall } }

  func write(_ line: String) throws {
    let message = try JSONValue(parsing: line)
    let closed = state.withLock { state in
      if !state.inputClosed { state.written.append(message) }
      return state.inputClosed
    }
    guard !closed else { throw AgentError.notRunning }
  }

  func closeInput() { state.withLock { $0.inputClosed = true } }

  func signal(_ signal: Int32) {
    state.withLock { $0.inputClosed = true }
    exit(128 + signal)
  }

  func waitForExit() async -> Int32 {
    await withCheckedContinuation { waiter in
      let status = state.withLock { state in
        if state.exitStatus == nil { state.exitWaiters.append(waiter) }
        return state.exitStatus
      }
      if let status { waiter.resume(returning: status) }
    }
  }

  private func play(_ script: [String], exitAfterScript: Int32?, timeout: Duration) async {
    let scriptedResponses = Set(
      script.compactMap { line -> String? in
        guard let message = try? JSONValue(parsing: line),
          message["type"]?.string == "control_response"
        else { return nil }
        return message["response"]?["request_id"]?.string
      })
    var answered: Set<String> = []
    var inits = 0
    var awaitingAnswer: String?
    for line in script {
      guard let message = try? JSONValue(parsing: line) else { continue }
      if let id = awaitingAnswer {
        guard
          await gate(
            "answer to \(id)", timeout, scriptedResponses, &answered,
            { written in
              written.contains { $0["response"]?["request_id"]?.string == id }
            })
        else { return finish(exitAfterScript) }
        awaitingAnswer = nil
      }
      switch (message["type"]?.string, message["subtype"]?.string) {
      case ("system", "init"):
        inits += 1
        let needed = inits
        guard
          await gate(
            "user message \(needed)", timeout, scriptedResponses, &answered,
            { written in
              written.filter { $0["type"]?.string == "user" }.count >= needed
            })
        else { return finish(exitAfterScript) }
      case ("control_response", _):
        let id = message["response"]?["request_id"]?.string
        guard
          await gate(
            "control request \(id ?? "?")", timeout, scriptedResponses, &answered,
            {
              written in written.contains { $0["request_id"]?.string == id }
            })
        else { return finish(exitAfterScript) }
      default:
        break
      }
      continuation.yield(line)
      if message["type"]?.string == "control_request" {
        awaitingAnswer = message["request_id"]?.string
      }
    }
    if exitAfterScript == nil {
      _ = await gate("end of input", nil, scriptedResponses, &answered) { _ in false }
    }
    finish(exitAfterScript)
  }

  /// Waits for `condition` on what was written, answering unscripted control requests
  /// meanwhile. False when stdin closed or the wait timed out (recorded in `stall`).
  private func gate(
    _ description: String, _ timeout: Duration?, _ scripted: Set<String>,
    _ answered: inout Set<String>, _ condition: ([JSONValue]) -> Bool
  ) async -> Bool {
    let deadline = timeout.map { ContinuousClock.now + $0 }
    while true {
      let (written, closed) = state.withLock { ($0.written, $0.inputClosed) }
      for request in written where request["type"]?.string == "control_request" {
        guard let id = request["request_id"]?.string, !scripted.contains(id),
          answered.insert(id).inserted
        else { continue }
        let reply: JSONValue = [
          "type": "control_response",
          "response": ["subtype": "success", "request_id": .string(id), "response": [:]],
        ]
        continuation.yield(reply.jsonString)
      }
      if condition(written) { return true }
      if closed { return false }
      if let deadline, ContinuousClock.now >= deadline {
        state.withLock { $0.stall = "waited for \(description)" }
        return false
      }
      try? await Task.sleep(for: .milliseconds(1))
    }
  }

  private func finish(_ status: Int32?) {
    continuation.finish()
    let closed = state.withLock { $0.inputClosed }
    exit(status ?? (closed ? 0 : 99))
  }

  private func exit(_ status: Int32) {
    let waiters = state.withLock { state in
      guard state.exitStatus == nil else { return [CheckedContinuation<Int32, Never>]() }
      state.exitStatus = status
      defer { state.exitWaiters.removeAll() }
      return state.exitWaiters
    }
    for waiter in waiters { waiter.resume(returning: status) }
  }
}

/// A backend over replayed transcripts: each launch takes the next transport.
final class ReplayLauncher: Sendable {
  private let state: Mutex<(transports: [ReplayTransport], launches: [ClaudeLaunch])>

  init(_ transports: [ReplayTransport]) { state = Mutex((transports, [])) }

  var launches: [ClaudeLaunch] { state.withLock { $0.launches } }

  func backend(
    config: ClaudeCodeConfig = ClaudeCodeConfig(), environment: [String: String] = [:],
    restartDelays: [Duration] = [.zero, .zero, .zero]
  ) -> ClaudeCodeBackend {
    ClaudeCodeBackend(
      config: config, locate: { URL(filePath: "/opt/bin/claude") },
      versionOutput: { _ in "2.1.302 (Claude Code)" }, environment: { environment },
      restartDelays: restartDelays,
      launcher: { [self] launch in
        try state.withLock { state in
          state.launches.append(launch)
          guard !state.transports.isEmpty else {
            throw AgentError.launchFailed("no more replay transports")
          }
          let transport = state.transports.removeFirst()
          transport.start()
          return transport
        }
      })
  }
}
