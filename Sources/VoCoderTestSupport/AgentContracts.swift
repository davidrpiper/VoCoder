// Agent contract suites (DESIGN §4.4, ADR 0010): the fake, Claude Code (over replayed
// transcripts) and the stubs all run them.
import Foundation
import Synchronization
import Testing
import VoCoderCore

/// Collects a session's events as they arrive and waits for the ones a test needs.
public final class AgentEventRecorder: Sendable {
  private let state = Mutex<(events: [AgentEvent], finished: Bool)>(([], false))

  public init(_ session: any AgentSession) {
    let events = session.events
    Task {
      for await event in events { self.state.withLock { $0.events.append(event) } }
      self.state.withLock { $0.finished = true }
    }
  }

  public var events: [AgentEvent] { state.withLock { $0.events } }
  /// The stream has ended.
  public var isFinished: Bool { state.withLock { $0.finished } }

  public struct Timeout: Error, CustomStringConvertible {
    public let waitingFor: String
    public let events: [AgentEvent]
    public var description: String {
      "timed out waiting for \(waitingFor); got:\n"
        + events.map { "  \($0)" }.joined(separator: "\n")
    }
  }

  /// Waits until `condition` holds for the events so far.
  @discardableResult
  public func wait(
    for description: String = "condition", timeout: Duration = .seconds(10),
    until condition: ([AgentEvent], Bool) -> Bool
  ) async throws -> [AgentEvent] {
    let deadline = ContinuousClock.now + timeout
    while true {
      let (events, finished) = state.withLock { ($0.events, $0.finished) }
      if condition(events, finished) { return events }
      if finished || ContinuousClock.now >= deadline {
        throw Timeout(waitingFor: description, events: events)
      }
      try await Task.sleep(for: .milliseconds(2))
    }
  }

  /// The `occurrence`-th event `extract` matches (1-based).
  public func next<T>(
    _ extract: (AgentEvent) -> T?, occurrence: Int = 1, timeout: Duration = .seconds(10)
  ) async throws -> T {
    let events = try await wait(for: "match #\(occurrence) of \(T.self)", timeout: timeout) {
      events, _ in events.compactMap(extract).count >= occurrence
    }
    return events.compactMap(extract)[occurrence - 1]
  }

  /// Waits for the end of the stream.
  public func finish(timeout: Duration = .seconds(10)) async throws {
    try await wait(for: "the end of the stream", timeout: timeout) { _, finished in finished }
  }
}

/// Case accessors for matching events in tests.
extension AgentEvent {
  public var sessionStarted: AgentSessionInfo? {
    if case .sessionStarted(let value) = self { value } else { nil }
  }
  public var text: AgentText? { if case .text(let value) = self { value } else { nil } }
  public var textDelta: AgentTextDelta? {
    if case .textDelta(let value) = self { value } else { nil }
  }
  public var toolUse: AgentToolUse? { if case .toolUse(let value) = self { value } else { nil } }
  public var toolResult: AgentToolResult? {
    if case .toolResult(let value) = self { value } else { nil }
  }
  public var todos: [AgentTodo]? { if case .todos(let value) = self { value } else { nil } }
  public var permissionRequest: PermissionRequest? {
    if case .permissionRequest(let value) = self { value } else { nil }
  }
  public var backgroundTask: AgentBackgroundTask? {
    if case .backgroundTask(let value) = self { value } else { nil }
  }
  public var spokenSummary: String? {
    if case .spokenSummary(let value) = self { value } else { nil }
  }
  public var turnEnd: AgentTurnEnd? { if case .turnEnd(let value) = self { value } else { nil } }
  public var error: AgentError? { if case .error(let value) = self { value } else { nil } }
  public var ended: AgentEndReason? { if case .ended(let value) = self { value } else { nil } }
}

public enum AgentBackendContract {
  public static func verify(
    _ backend: any AgentBackend, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    ProviderContract.verify(backend, sourceLocation: sourceLocation)
    #expect(!backend.displayName.isEmpty, "display name is empty", sourceLocation: sourceLocation)
  }

  /// A stub: starting a session fails with `notImplemented`.
  public static func verifyStub(
    _ backend: any AgentBackend, sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    verify(backend, sourceLocation: sourceLocation)
    await #expect(
      throws: AgentError.notImplemented(backend: backend.displayName),
      sourceLocation: sourceLocation
    ) {
      _ = try await backend.startSession(AgentSessionOptions(repo: URL(filePath: "/tmp")))
    }
  }
}

public enum AgentSessionContract {
  /// `backend` must answer `prompt` with one completed turn. Checks the session lifecycle:
  /// idle interrupt, one `sessionStarted` before the reply, no `<spoken>` in text, unknown
  /// permission answers, and `close` ending the stream with `.ended(.closed)`.
  public static func verify(
    _ backend: any AgentBackend, options: AgentSessionOptions, prompt: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    AgentBackendContract.verify(backend, sourceLocation: sourceLocation)
    let session = try await backend.startSession(options)
    let recorder = AgentEventRecorder(session)

    await session.interrupt()  // idle: harmless
    try await session.send(prompt)
    let end = try await recorder.next(\.turnEnd)
    #expect(end.outcome == .completed, sourceLocation: sourceLocation)

    let events = recorder.events
    let starts = events.indices.filter { events[$0].sessionStarted != nil }
    #expect(starts.count == 1, "sessionStarted \(starts.count)×", sourceLocation: sourceLocation)
    let firstReply = events.firstIndex { $0.text != nil || $0.turnEnd != nil }
    if let start = starts.first, let firstReply {
      #expect(start < firstReply, "sessionStarted after the reply", sourceLocation: sourceLocation)
    }
    let tagged = events.compactMap(\.text).filter { $0.text.contains(SpokenTag.open) }
    #expect(tagged.isEmpty, "text with <spoken>: \(tagged)", sourceLocation: sourceLocation)

    let unknown = PermissionRequest(id: "contract-unknown", toolName: "Bash", input: [:])
    await #expect(
      throws: AgentError.unknownRequest("contract-unknown"), sourceLocation: sourceLocation
    ) { try await session.respond(to: unknown, .allowOnce) }

    await session.close()
    try await recorder.finish()
    let ends = recorder.events.compactMap(\.ended)
    #expect(ends == [.closed], sourceLocation: sourceLocation)
    #expect(recorder.events.last?.ended == .closed, sourceLocation: sourceLocation)
    await #expect(throws: AgentError.notRunning, sourceLocation: sourceLocation) {
      try await session.send("after close")
    }
    await session.close()
  }
}
