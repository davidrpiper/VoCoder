import Foundation
import Synchronization
import VoCoderCore

/// An agent backend whose sessions run a scripted `Behavior` per prompt: UI tests, snapshot
/// fixtures and `--demo`. The default behavior echoes the prompt in one completed turn.
public final class FakeAgentBackend: AgentBackend {
  /// What a session does with one prompt (runs in its own task, after the previous turn).
  public typealias Behavior = @Sendable (FakeAgentSession, String) async -> Void

  public let id: ProviderID
  public let displayName: String
  private let behavior: Behavior
  private let failure: AgentError?
  private let started = Mutex<[FakeAgentSession]>([])

  /// `failure` makes `startSession` throw it.
  public init(
    id: ProviderID = "fake-agent", displayName: String = "Fake agent",
    failure: AgentError? = nil, behavior: @escaping Behavior = FakeAgentBackend.echo
  ) {
    self.id = id
    self.displayName = displayName
    self.failure = failure
    self.behavior = behavior
  }

  /// Sessions started so far, oldest first.
  public var sessions: [FakeAgentSession] { started.withLock { $0 } }

  public func startSession(_ options: AgentSessionOptions) async throws -> any AgentSession {
    if let failure { throw failure }
    let session = started.withLock { started in
      let session = FakeAgentSession(
        options: options,
        id: options.resume ?? AgentSessionID("fake-session-\(started.count + 1)"),
        behavior: behavior)
      started.append(session)
      return session
    }
    return session
  }

  /// One turn: "You said: <prompt>", a spoken summary, completed.
  public static let echo: Behavior = { session, prompt in
    session.beginTurn()
    session.emit(.text(AgentText(messageID: session.nextMessageID(), text: "You said: \(prompt)")))
    session.emit(.spokenSummary("You said \(prompt)"))
    session.endTurn(.completed)
  }
}

/// A fake session. Behaviors drive it with `beginTurn`, `emit`, `requestPermission` and
/// `endTurn`; tests read what the app did through `prompts`, `decisions` and `interrupts`.
public final class FakeAgentSession: AgentSession {
  public let options: AgentSessionOptions
  public let id: AgentSessionID
  public let events: AsyncStream<AgentEvent>
  private let continuation: AsyncStream<AgentEvent>.Continuation
  private let behavior: FakeAgentBackend.Behavior
  private let state = Mutex(State())

  private struct State {
    var prompts: [String] = []
    var decisions: [(request: PermissionRequest, decision: PermissionDecision)] = []
    var interrupts = 0
    var closed = false
    var announced = false
    var turnActive = false
    var messages = 0
    var pending: [String: (PermissionRequest, CheckedContinuation<PermissionDecision, Never>)] =
      [:]
    var lastTurn: Task<Void, Never>?
  }

  init(
    options: AgentSessionOptions, id: AgentSessionID, behavior: @escaping FakeAgentBackend.Behavior
  ) {
    self.options = options
    self.id = id
    self.behavior = behavior
    (events, continuation) = AsyncStream.makeStream()
  }

  public var prompts: [String] { state.withLock { $0.prompts } }
  public var decisions: [(request: PermissionRequest, decision: PermissionDecision)] {
    state.withLock { $0.decisions }
  }
  public var interrupts: Int { state.withLock { $0.interrupts } }
  public var isClosed: Bool { state.withLock { $0.closed } }

  // MARK: AgentSession

  public func send(_ prompt: String) async throws {
    try state.withLock { state in
      guard !state.closed else { throw AgentError.notRunning }
      state.prompts.append(prompt)
      let previous = state.lastTurn
      state.lastTurn = Task { [behavior] in
        await previous?.value
        guard !Task.isCancelled else { return }
        await behavior(self, prompt)
      }
    }
  }

  public func respond(to request: PermissionRequest, _ decision: PermissionDecision)
    async throws
  {
    let waiter = try state.withLock { state in
      guard let (_, waiter) = state.pending.removeValue(forKey: request.id) else {
        throw AgentError.unknownRequest(request.id)
      }
      state.decisions.append((request, decision))
      return waiter
    }
    waiter.resume(returning: decision)
  }

  public func interrupt() async {
    let (wasActive, turn, waiters) = state.withLock { state in
      state.interrupts += 1
      defer {
        state.turnActive = false
        state.pending.removeAll()
      }
      return (state.turnActive, state.lastTurn, state.pending.values.map(\.1))
    }
    guard wasActive else { return }
    turn?.cancel()
    for waiter in waiters { waiter.resume(returning: .deny(message: "interrupted")) }
    continuation.yield(.turnEnd(AgentTurnEnd(outcome: .interrupted)))
  }

  public func close() async {
    let (alreadyClosed, turn, waiters) = state.withLock { state in
      defer {
        state.closed = true
        state.pending.removeAll()
      }
      return (state.closed, state.lastTurn, state.pending.values.map(\.1))
    }
    guard !alreadyClosed else { return }
    turn?.cancel()
    for waiter in waiters { waiter.resume(returning: .deny(message: "closed")) }
    continuation.yield(.ended(.closed))
    continuation.finish()
  }

  // MARK: Scripting

  /// Starts a turn; the first one also announces the session.
  public func beginTurn() {
    let announce = state.withLock { state in
      state.turnActive = true
      defer { state.announced = true }
      return !state.announced
    }
    if announce {
      continuation.yield(.sessionStarted(AgentSessionInfo(id: id, model: "fake")))
    }
  }

  /// Reports an event, unless the turn was interrupted or the session closed.
  public func emit(_ event: AgentEvent) {
    guard !Task.isCancelled, !isClosed else { return }
    continuation.yield(event)
  }

  public func endTurn(_ outcome: AgentTurnEnd.Outcome, text: String? = nil) {
    guard !Task.isCancelled else { return }
    state.withLock { $0.turnActive = false }
    emit(.turnEnd(AgentTurnEnd(outcome: outcome, text: text)))
  }

  /// Emits `.permissionRequest` and waits for the app's answer (`deny` if the turn is
  /// interrupted or the session closed first).
  public func requestPermission(_ request: PermissionRequest) async -> PermissionDecision {
    await withCheckedContinuation { waiter in
      let accepted = state.withLock { state in
        guard !state.closed, state.turnActive else { return false }
        state.pending[request.id] = (request, waiter)
        return true
      }
      guard accepted else {
        waiter.resume(returning: .deny(message: "not running"))
        return
      }
      continuation.yield(.permissionRequest(request))
    }
  }

  /// "fake-msg-1", "fake-msg-2", …
  public func nextMessageID() -> String {
    state.withLock { state in
      state.messages += 1
      return "fake-msg-\(state.messages)"
    }
  }
}
