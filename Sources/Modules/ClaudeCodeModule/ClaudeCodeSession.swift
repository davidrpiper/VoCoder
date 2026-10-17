import Foundation
import VoCoderCore

/// One long-lived `claude -p` stream-json process (ADR 0002), restarted with `--resume` if it
/// dies unexpectedly (ADR 0010).
public actor ClaudeCodeSession: AgentSession {
  public nonisolated let events: AsyncStream<AgentEvent>
  private let continuation: AsyncStream<AgentEvent>.Continuation
  private let makeLaunch: @Sendable (AgentSessionID?) -> ClaudeLaunch
  private let launcher: ClaudeLauncher
  private let restartDelays: [Duration]
  private let minimumVersion: CLIVersion
  private let startupTimeout: Duration
  private let log: Log

  private enum Phase { case starting, running, restarting, closing, ended }

  private var phase = Phase.starting
  private var transport: (any ClaudeTransport)?
  /// Which process the reader callbacks belong to; output of a replaced process is ignored.
  private var generation = 0
  private var mapper = ClaudeEventMapper()
  private var resumeID: AgentSessionID?
  /// Our control request ids (`vc-N`), numbered per process.
  private var nextRequest = 1
  private var pendingControls: [String: CheckedContinuation<JSONValue, any Error>] = [:]
  private var pendingPermissions: [String: (input: JSONValue, suggestions: [JSONValue])] = [:]
  private var restartAttempt = 0
  private var turnRunning = false
  /// Prompts sent while restarting; written once the new process is up.
  private var queuedPrompts: [String] = []
  private var lastFailure: String?
  private var versionReported = false

  /// Spawns the process and returns once it answered `initialize`.
  public static func start(
    resume: AgentSessionID?, minimumVersion: CLIVersion,
    restartDelays: [Duration] = [.milliseconds(500), .seconds(2), .seconds(5)],
    startupTimeout: Duration = .seconds(30), log: Log = Log(category: "agent.claude-code"),
    launcher: @escaping ClaudeLauncher,
    makeLaunch: @escaping @Sendable (AgentSessionID?) -> ClaudeLaunch
  ) async throws -> ClaudeCodeSession {
    let session = ClaudeCodeSession(
      resume: resume, minimumVersion: minimumVersion, restartDelays: restartDelays,
      startupTimeout: startupTimeout, log: log, launcher: launcher, makeLaunch: makeLaunch)
    try await session.begin()
    return session
  }

  private init(
    resume: AgentSessionID?, minimumVersion: CLIVersion, restartDelays: [Duration],
    startupTimeout: Duration, log: Log, launcher: @escaping ClaudeLauncher,
    makeLaunch: @escaping @Sendable (AgentSessionID?) -> ClaudeLaunch
  ) {
    (events, continuation) = AsyncStream.makeStream()
    resumeID = resume
    self.minimumVersion = minimumVersion
    self.restartDelays = restartDelays
    self.startupTimeout = startupTimeout
    self.log = log
    self.launcher = launcher
    self.makeLaunch = makeLaunch
  }

  private func begin() async throws {
    do {
      try await connect()
      phase = .running
    } catch {
      phase = .ended
      continuation.finish()
      throw error
    }
  }

  // MARK: - AgentSession

  public func send(_ prompt: String) async throws {
    switch phase {
    case .ended, .closing: throw AgentError.notRunning
    case .starting, .restarting: queuedPrompts.append(prompt)
    case .running:
      do {
        try write(Self.userMessage(prompt))
      } catch {
        // The process is going away; resend after the restart.
        queuedPrompts.append(prompt)
      }
    }
  }

  public func respond(to request: PermissionRequest, _ decision: PermissionDecision)
    async throws
  {
    guard let pending = pendingPermissions.removeValue(forKey: request.id) else {
      throw AgentError.unknownRequest(request.id)
    }
    guard phase == .running else { throw AgentError.notRunning }
    let response = Self.decision(decision, input: pending.input, suggestions: pending.suggestions)
    try write(
      [
        "type": "control_response",
        "response": [
          "subtype": "success", "request_id": .string(request.id), "response": response,
        ],
      ])
  }

  public func interrupt() async {
    guard phase == .running else { return }
    do {
      _ = try await control(["subtype": "interrupt"], timeout: .seconds(5))
    } catch {
      log.notice("interrupt: \(error)")
    }
  }

  public func close() async {
    switch phase {
    case .ended, .closing: return
    case .starting, .running, .restarting: break
    }
    phase = .closing
    if let transport {
      _ = await transport.stop()  // the reader then finishes with `.ended(.closed)`
    } else {
      finish(.closed)
    }
  }

  // MARK: - Process

  private func connect() async throws {
    let transport = try launcher(makeLaunch(resumeID))
    generation += 1
    let generation = generation
    self.transport = transport
    nextRequest = 1
    mapper.resetStream()
    Task {
      for await line in transport.lines { self.receive(line, generation: generation) }
      let status = await transport.waitForExit()
      await self.transportEnded(status: status, generation: generation)
    }
    do {
      _ = try await control(["subtype": "initialize"], timeout: startupTimeout)
    } catch {
      _ = await transport.stop(grace: .milliseconds(500))
      let stderr = transport.recentErrorOutput.split(separator: "\n").last.map(String.init)
      throw AgentError.launchFailed(lastFailure ?? stderr ?? "\(error)")
    }
  }

  private func receive(_ line: String, generation: Int) {
    guard generation == self.generation else { return }
    for output in mapper.map(line: line) {
      switch output {
      case .event(let event):
        handle(event)
      case .controlResponse(let id, let result):
        pendingControls.removeValue(forKey: id)?.resume(
          with: result.mapError { AgentError.protocolViolation($0.message) })
      case .permission(let request, let suggestions):
        pendingPermissions[request.id] = (request.input, suggestions)
        continuation.yield(.permissionRequest(request))
      case .unsupportedControl(let id, let subtype):
        log.notice("unsupported control request \(subtype)")
        try? write(
          [
            "type": "control_response",
            "response": [
              "subtype": "error", "request_id": .string(id),
              "error": .string("VoCoder doesn't support \(subtype)"),
            ],
          ])
      case .turnStarted(let info):
        resumeID = info.id
        turnRunning = true
        checkVersion(info.agentVersion)
      }
    }
  }

  private func handle(_ event: AgentEvent) {
    if case .turnEnd(let end) = event {
      turnRunning = false
      // A permission request can't outlive its turn; late answers get `unknownRequest`.
      pendingPermissions.removeAll()
      switch end.outcome {
      case .completed: restartAttempt = 0
      case .failed(let message): lastFailure = message
      case .interrupted: break
      }
    }
    if case .error(let error) = event { log.error("\(error)") }
    continuation.yield(event)
  }

  private func checkVersion(_ text: String?) {
    guard !versionReported, let text, let version = CLIVersion(text), version < minimumVersion
    else { return }
    versionReported = true
    handle(.error(.unsupportedVersion(found: text, minimum: minimumVersion.description)))
  }

  private func transportEnded(status: Int32, generation: Int) async {
    guard generation == self.generation else { return }
    transport = nil
    let failure = AgentError.launchFailed("the agent exited (status \(status))")
    for pending in pendingControls.values { pending.resume(throwing: failure) }
    pendingControls.removeAll()
    pendingPermissions.removeAll()
    switch phase {
    case .closing:
      finish(.closed)
    case .running:
      log.error("claude exited unexpectedly with status \(status)")
      if turnRunning {
        turnRunning = false
        continuation.yield(.turnEnd(AgentTurnEnd(outcome: .failed("the agent exited"))))
      }
      await restart(after: status)
    case .starting, .restarting, .ended:
      break  // `connect()` reports it
    }
  }

  private func restart(after status: Int32) async {
    phase = .restarting
    while restartAttempt < restartDelays.count {
      let delay = restartDelays[restartAttempt]
      restartAttempt += 1
      handle(.error(.crashed(status: status, restarting: restartAttempt)))
      try? await Task.sleep(for: delay)
      guard phase == .restarting else { return }
      do {
        try await connect()
        guard phase == .restarting else { return }
        phase = .running
        let prompts = queuedPrompts
        queuedPrompts.removeAll()
        for prompt in prompts { try await send(prompt) }
        return
      } catch {
        guard phase == .restarting else { return }
        log.error("restart \(restartAttempt) failed: \(error)")
      }
    }
    handle(.error(.crashed(status: status, restarting: nil)))
    finish(.exited(status: status))
  }

  private func finish(_ reason: AgentEndReason) {
    guard phase != .ended else { return }
    phase = .ended
    continuation.yield(.ended(reason))
    continuation.finish()
  }

  // MARK: - Writing

  private func write(_ message: JSONValue) throws {
    guard let transport else { throw AgentError.notRunning }
    try transport.write(message.jsonString)
  }

  private func control(_ request: JSONValue, timeout: Duration) async throws -> JSONValue {
    let id = "vc-\(nextRequest)"
    nextRequest += 1
    let message: JSONValue = [
      "type": "control_request", "request_id": .string(id), "request": request,
    ]
    return try await withCheckedThrowingContinuation { continuation in
      pendingControls[id] = continuation
      do {
        try write(message)
      } catch {
        pendingControls[id] = nil
        continuation.resume(throwing: error)
        return
      }
      Task { [weak self] in
        try? await Task.sleep(for: timeout)
        await self?.timeOut(id)
      }
    }
  }

  private func timeOut(_ id: String) {
    pendingControls.removeValue(forKey: id)?.resume(
      throwing: AgentError.protocolViolation("no reply to control request \(id)"))
  }

  static func userMessage(_ prompt: String) -> JSONValue {
    ["type": "user", "message": ["role": "user", "content": .string(prompt)]]
  }

  /// The `can_use_tool` answer (FINDINGS "Input"). `allowEdited`'s input replaces the
  /// requested one; session rules rewrite the CLI's suggestions to `destination: session`.
  static func decision(
    _ decision: PermissionDecision, input: JSONValue, suggestions: [JSONValue]
  ) -> JSONValue {
    func allow(_ input: JSONValue, rules: [JSONValue] = []) -> JSONValue {
      var object: [String: JSONValue] = ["behavior": "allow", "updatedInput": input]
      if !rules.isEmpty { object["updatedPermissions"] = .array(rules) }
      return .object(object)
    }
    switch decision {
    case .allowOnce: return allow(input)
    case .allowEdited(let edited): return allow(edited)
    case .allowAlways: return allow(input, rules: suggestions)
    case .allowForSession:
      return allow(
        input,
        rules: suggestions.map { suggestion in
          guard var object = suggestion.object else { return suggestion }
          object["destination"] = "session"
          return .object(object)
        })
    case .deny(let message): return ["behavior": "deny", "message": .string(message)]
    }
  }
}
