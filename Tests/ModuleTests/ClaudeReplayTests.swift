import ClaudeCodeModule
import Foundation
import Testing
import VoCoderCore
import VoCoderTestSupport

/// Replays the P0-04 transcripts through the real session code (ADR 0010).
@Suite struct ClaudeReplayTests {
  let repo = URL(filePath: "/REPO/test")

  /// One line per event, leaving out status, usage and streaming noise.
  static func summary(_ events: [AgentEvent]) -> [String] {
    events.compactMap { event in
      switch event {
      case .sessionStarted(let info): "started \(info.model ?? "?") \(info.agentVersion ?? "?")"
      case .text(let text): "text \(text.text.prefix(30))"
      case .toolUse(let use): "tool \(use.name)"
      case .toolResult(let result):
        "result \(result.toolName ?? "?")\(result.isError ? " error" : "")"
      case .todos(let todos):
        "todos " + todos.map { "\($0.subject):\($0.status.rawValue)" }.joined(separator: ",")
      case .permissionRequest(let request): "permission \(request.toolName)"
      case .backgroundTask(let task): "task \(task.status.rawValue)"
      case .spokenSummary: "spoken"
      case .turnEnd(let end): "turn \(end.outcome)"
      case .error(let error): "error \(error)"
      case .ended(let reason): "ended \(reason)"
      case .status, .usage, .textDelta: nil
      }
    }
  }

  func start(
    _ fixture: ClaudeFixture, resume: AgentSessionID? = nil
  ) async throws -> (any AgentSession, AgentEventRecorder, ReplayTransport, ReplayLauncher) {
    let transport = ReplayTransport(fixture)
    let launcher = ReplayLauncher([transport])
    let session = try await launcher.backend().startSession(
      AgentSessionOptions(repo: repo, resume: resume))
    return (session, AgentEventRecorder(session), transport, launcher)
  }

  @Test func replayRunsTheContract() async throws {
    let fixture = try ClaudeFixture("multiturn")
    try await AgentSessionContract.verify(
      ReplayLauncher([ReplayTransport(fixture)]).backend(),
      options: AgentSessionOptions(repo: repo), prompt: fixture.prompts[0])
  }

  @Test func multiturn() async throws {
    let fixture = try ClaudeFixture("multiturn")
    let (session, recorder, transport, launcher) = try await start(fixture)
    for (index, prompt) in fixture.prompts.enumerated() {
      try await session.send(prompt)
      _ = try await recorder.next(\.turnEnd, occurrence: index + 1)
    }
    await session.close()
    try await recorder.finish()
    #expect(transport.stall == nil)
    #expect(
      Self.summary(recorder.events) == [
        "started claude-haiku-5-5 2.1.302", "text one", "turn completed", "text One",
        "turn completed", "text three", "turn completed", "text alpha", "turn completed",
        "text beta", "turn completed", "ended closed",
      ])
    let launch = try #require(launcher.launches.first)
    #expect(launch.directory == repo)
    #expect(launch.arguments.contains("--permission-prompt-tool"))
    #expect(!launch.arguments.contains("--resume"))
    #expect(launcher.launches.count == 1)
  }

  /// Sends each prompt and waits for its turn to end, answering permission requests with
  /// `decisions` in order.
  func drive(
    _ session: any AgentSession, _ recorder: AgentEventRecorder, prompts: [String],
    decisions: [PermissionDecision] = []
  ) async throws {
    var decisions = decisions[...]
    var answered = 0
    for (index, prompt) in prompts.enumerated() {
      try await session.send(prompt)
      while true {
        let events = try await recorder.wait(for: "turn \(index + 1) or a permission") {
          events, _ in
          events.compactMap(\.turnEnd).count > index
            || events.compactMap(\.permissionRequest).count > answered
        }
        let requests = events.compactMap(\.permissionRequest)
        if requests.count > answered {
          let next = decisions.popFirst()
          let decision = try #require(next, "unexpected \(requests[answered])")
          try await session.respond(to: requests[answered], decision)
          answered += 1
        } else {
          break
        }
      }
    }
    #expect(decisions.isEmpty, "unused decisions \(decisions)")
  }

  @Test func permissions() async throws {
    let fixture = try ClaudeFixture("permission-host")
    let (session, recorder, transport, _) = try await start(fixture)
    let edited = try #require(
      fixture.permissionAnswers[2]["response"]?["response"]?["updatedInput"])
    try await drive(
      session, recorder, prompts: fixture.prompts,
      decisions: [
        .allowOnce, .deny(message: "The user declined this from VoCoder."), .allowEdited(edited),
        .allowAlways, .deny(message: "should not have been asked"), .allowForSession,
      ])
    await session.close()
    try await recorder.finish()
    #expect(transport.stall == nil)
    // Byte for byte what the spike answered (rules rewritten to `session` for the 6th).
    let answers = transport.written.filter { $0["type"]?.string == "control_response" }
    #expect(answers == fixture.permissionAnswers)

    let requests = recorder.events.compactMap(\.permissionRequest)
    #expect(requests.count == 6)
    let first = try #require(requests.first)
    #expect(first.toolName == "Bash")
    #expect(first.input["command"]?.string == "echo approved > a.txt")
    #expect(first.description == "Write \"approved\" into a.txt")
    #expect(first.blockedPath == "/REPO/permission-host/a.txt")
    #expect(first.offersSessionRule)
    let denied = recorder.events.compactMap(\.toolResult).filter(\.isError)
    #expect(denied.map(\.content).contains("The user declined this from VoCoder."))
    #expect(recorder.events.compactMap(\.turnEnd).allSatisfy { $0.outcome == .completed })
  }

  @Test func interrupts() async throws {
    let fixture = try ClaudeFixture("interrupt")
    let (session, recorder, transport, _) = try await start(fixture)
    let prompts = fixture.prompts
    try await session.send(prompts[0])
    let request = try await recorder.next(\.permissionRequest)
    let answer = try #require(fixture.permissionAnswers[0]["response"]?["response"])
    try await session.respond(to: request, .allowEdited(try #require(answer["updatedInput"])))
    let task = try await recorder.next(\.backgroundTask)
    #expect(task.status == .running)
    #expect(task.description == "Sleep 30 seconds then print finished")
    await session.interrupt()
    #expect(try await recorder.next(\.turnEnd).outcome == .interrupted)
    #expect(try await recorder.next(\.backgroundTask, occurrence: 2).status == .stopped)

    try await session.send(prompts[1])  // a long story, interrupted while streaming
    await session.interrupt()
    #expect(try await recorder.next(\.turnEnd, occurrence: 2).outcome == .interrupted)
    try await session.send(prompts[2])
    #expect(try await recorder.next(\.turnEnd, occurrence: 3).outcome == .completed)
    try await session.send(prompts[3])
    await session.interrupt()
    #expect(try await recorder.next(\.turnEnd, occurrence: 4).outcome == .interrupted)
    await session.close()
    try await recorder.finish()
    #expect(transport.stall == nil)
    #expect(recorder.events.compactMap(\.text).contains { $0.text == "still here" })
  }

  @Test func streamedTextMatchesTheBlocks() async throws {
    let fixture = try ClaudeFixture("partial")
    let (session, recorder, _, _) = try await start(fixture)
    try await drive(session, recorder, prompts: fixture.prompts)
    await session.close()
    try await recorder.finish()
    let deltas = recorder.events.compactMap(\.textDelta)
    #expect(deltas.count >= 2)
    let texts = recorder.events.compactMap(\.text)
    for text in texts {
      let streamed = deltas.filter { $0.messageID == text.messageID }.map(\.text).joined()
      #expect(SpokenTag.extract(from: streamed).text == text.text)
    }
    #expect(!texts.isEmpty)
  }

  @Test func todosFromTaskTools() async throws {
    let fixture = try ClaudeFixture("todos")
    let (session, recorder, _, _) = try await start(fixture)
    try await drive(session, recorder, prompts: fixture.prompts)
    await session.close()
    try await recorder.finish()
    let lists = recorder.events.compactMap(\.todos)
    #expect(lists.count == 5)
    #expect(
      lists.last == [
        AgentTodo(id: "1", subject: "lint", status: .inProgress),
        AgentTodo(id: "2", subject: "test", status: .completed),
        AgentTodo(id: "3", subject: "ship", status: .pending),
      ])
    let results = recorder.events.compactMap(\.toolResult)
    #expect(results.allSatisfy { $0.toolName?.hasPrefix("Task") == true })
  }

  @Test func resumePassesTheSessionID() async throws {
    let first = try ClaudeFixture("resume-1")
    let (session, recorder, _, _) = try await start(first)
    try await drive(session, recorder, prompts: first.prompts)
    let id = try #require(recorder.events.compactMap(\.sessionStarted).first?.id)
    await session.close()

    let second = try ClaudeFixture("resume-2")
    let (resumed, resumedRecorder, _, launcher) = try await start(second, resume: id)
    try await drive(resumed, resumedRecorder, prompts: second.prompts)
    await resumed.close()
    let arguments = try #require(launcher.launches.first?.arguments)
    #expect(arguments.suffix(2) == ["--resume", id.rawValue])
    #expect(resumedRecorder.events.compactMap(\.sessionStarted).map(\.id) == [id])
  }

  @Test func unknownResumeIDFailsToStart() async throws {
    let fixture = try ClaudeFixture("resume-5-unknown")
    let launcher = ReplayLauncher([ReplayTransport(fixture, exitAfterScript: 1)])
    await #expect(
      throws: AgentError.launchFailed(
        "No conversation found with session ID: d2b51441-1ce3-4abd-90d0-9d9ea1f836a7")
    ) {
      _ = try await launcher.backend().startSession(
        AgentSessionOptions(repo: repo, resume: "d2b51441-1ce3-4abd-90d0-9d9ea1f836a7"))
    }
  }

  @Test func crashRestartsWithResume() async throws {
    let killed = try ClaudeFixture("resume-3-killed")
    let after = try ClaudeFixture("resume-4-after-kill")
    let launcher = ReplayLauncher([
      ReplayTransport(killed, exitAfterScript: 128 + SIGKILL), ReplayTransport(after),
    ])
    let session = try await launcher.backend().startSession(AgentSessionOptions(repo: repo))
    let recorder = AgentEventRecorder(session)
    try await drive(session, recorder, prompts: [killed.prompts[0]])
    let id = try #require(recorder.events.compactMap(\.sessionStarted).first?.id)
    try await session.send(killed.prompts[1])
    #expect(
      try await recorder.next(\.turnEnd, occurrence: 2).outcome == .failed("the agent exited"))
    #expect(try await recorder.next(\.error) == .crashed(status: 137, restarting: 1))
    // Sent while restarting: queued, then answered by the resumed process.
    try await session.send(after.prompts[0])
    #expect(try await recorder.next(\.turnEnd, occurrence: 3).outcome == .completed)
    await session.close()
    try await recorder.finish()
    #expect(launcher.launches.count == 2)
    #expect(launcher.launches.last?.arguments.suffix(2) == ["--resume", id.rawValue])
    #expect(recorder.events.compactMap(\.sessionStarted).count == 1)
    #expect(recorder.events.last == .ended(.closed))
  }

  @Test func restartsGiveUpAfterTheLastAttempt() async throws {
    let fixture = try ClaudeFixture("resume-1")
    let launcher = ReplayLauncher([ReplayTransport(fixture, exitAfterScript: 1)])
    let session = try await launcher.backend().startSession(AgentSessionOptions(repo: repo))
    let recorder = AgentEventRecorder(session)
    try await drive(session, recorder, prompts: fixture.prompts)
    try await recorder.finish()
    #expect(
      recorder.events.compactMap(\.error) == [
        .crashed(status: 1, restarting: 1), .crashed(status: 1, restarting: 2),
        .crashed(status: 1, restarting: 3), .crashed(status: 1, restarting: nil),
      ])
    #expect(recorder.events.last == .ended(.exited(status: 1)))
    #expect(launcher.launches.count == 4)
    await #expect(throws: AgentError.notRunning) { try await session.send("hello?") }
  }

  @Test func spokenSummaries() async throws {
    let fixture = try ClaudeFixture("spoken-haiku")
    let (session, recorder, transport, _) = try await start(fixture)
    let decisions = try fixture.permissionAnswers.map { answer -> PermissionDecision in
      let response = try #require(answer["response"]?["response"])
      if response["behavior"]?.string == "deny" {
        return .deny(message: response["message"]?.string ?? "")
      }
      return .allowEdited(try #require(response["updatedInput"]))
    }
    try await drive(session, recorder, prompts: fixture.prompts, decisions: decisions)
    await session.close()
    try await recorder.finish()
    #expect(
      transport.written.filter { $0["type"]?.string == "control_response" }
        == fixture.permissionAnswers)
    let spoken = recorder.events.compactMap(\.spokenSummary)
    #expect(spoken.count == 15)
    #expect(spoken.allSatisfy { !$0.isEmpty && !$0.contains("<") })
    let texts =
      recorder.events.compactMap(\.text).map(\.text)
      + recorder.events.compactMap(\.turnEnd).compactMap(\.text)
    #expect(texts.allSatisfy { !$0.contains(SpokenTag.open) && !$0.contains(SpokenTag.close) })
  }
}
