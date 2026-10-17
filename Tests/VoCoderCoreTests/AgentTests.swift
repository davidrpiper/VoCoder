import Foundation
import Testing
import VoCoderCore
import VoCoderFakes
import VoCoderTestSupport

@Suite struct AgentTypeTests {
  @Test func jsonValueRoundTrips() throws {
    let text = #"{"a":[1,2.5,true,null,"x"],"b":{"c":"d/e"}}"#
    let value = try JSONValue(parsing: text)
    #expect(value["a"]?.array?.count == 5)
    #expect(value["a"]?.array?[0] == .int(1))
    #expect(value["a"]?.array?[1].double == 2.5)
    #expect(value["a"]?.array?[2].bool == true)
    #expect(value["b"]?["c"]?.string == "d/e")
    #expect(value.jsonString == text)
    #expect(try JSONValue(parsing: value.jsonString) == value)
    #expect(JSONValue.object(["k": [1, "two"]]).jsonString == #"{"k":[1,"two"]}"#)
  }

  @Test func spokenTagIsExtracted() {
    let reply = "Done.\n\nAll good.\n\n<spoken>I fixed the test.</spoken>\n"
    #expect(SpokenTag.extract(from: reply) == ("Done.\n\nAll good.", "I fixed the test."))
    #expect(SpokenTag.extract(from: "No tag") == ("No tag", nil))
    #expect(SpokenTag.extract(from: "<spoken> Only </spoken>") == ("", "Only"))
    #expect(SpokenTag.extract(from: "Cut <spoken>partial") == ("Cut", "partial"))
    #expect(SpokenTag.extract(from: "<spoken></spoken>x") == ("x", nil))
  }

  @Test func spokenTagFilterHandlesEverySplit() {
    let reply = "Hello <b>world</b>.\n<spoken>Said aloud.</spoken> tail <spo"
    for split in 1..<reply.count {
      for size in [1, 3, split] {
        var filter = SpokenTagFilter()
        var output = ""
        var rest = Substring(reply)
        while !rest.isEmpty {
          output += filter.feed(String(rest.prefix(size)))
          rest = rest.dropFirst(size)
        }
        output += filter.finish()
        #expect(output == "Hello <b>world</b>.\n tail <spo", "chunk size \(size)")
      }
    }
  }

  @Test func sessionStoreRemembersPerRepoAndBackend() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "sessions.json")
    let repo = URL(filePath: "/work/api")
    let store = AgentSessionStore(file: file)
    #expect(store.lastSession(repo: repo, backend: "claude-code") == nil)
    store.record("s-1", repo: repo, backend: "claude-code")
    store.record("s-2", repo: URL(filePath: "/work/api/../api/"), backend: "claude-code")
    store.record("x-1", repo: repo, backend: "codex")

    let reloaded = AgentSessionStore(file: file)
    #expect(reloaded.lastSession(repo: repo, backend: "claude-code") == "s-2")
    #expect(reloaded.lastSession(repo: repo, backend: "codex") == "x-1")
    reloaded.forget(repo: repo, backend: "claude-code")
    #expect(AgentSessionStore(file: file).lastSession(repo: repo, backend: "claude-code") == nil)

    try Data("garbage".utf8).write(to: file)
    #expect(AgentSessionStore(file: file).lastSession(repo: repo, backend: "codex") == nil)
  }
}

@Suite struct FakeAgentTests {
  let options = AgentSessionOptions(repo: URL(filePath: "/work/api"))

  @Test func fakeRunsTheContract() async throws {
    try await AgentSessionContract.verify(FakeAgentBackend(), options: options, prompt: "hi")
  }

  @Test func echoTurn() async throws {
    let backend = FakeAgentBackend()
    let session = try await backend.startSession(options)
    let recorder = AgentEventRecorder(session)
    try await session.send("hello")
    _ = try await recorder.next(\.turnEnd)
    #expect(
      recorder.events == [
        .sessionStarted(AgentSessionInfo(id: "fake-session-1", model: "fake")),
        .text(AgentText(messageID: "fake-msg-1", text: "You said: hello")),
        .spokenSummary("You said hello"),
        .turnEnd(AgentTurnEnd(outcome: .completed)),
      ])
    #expect(backend.sessions.first?.prompts == ["hello"])
  }

  @Test func scriptedPermissionAndInterrupt() async throws {
    let request = PermissionRequest(id: "p1", toolName: "Bash", input: ["command": "rm x"])
    let backend = FakeAgentBackend { session, prompt in
      session.beginTurn()
      if prompt == "wait" {
        _ = await session.requestPermission(
          PermissionRequest(id: "p2", toolName: "Bash", input: [:]))
        session.emit(.text(AgentText(messageID: "late", text: "should not appear")))
        return
      }
      let decision = await session.requestPermission(request)
      session.endTurn(.completed, text: "\(decision)")
    }
    let session = try await backend.startSession(options)
    let recorder = AgentEventRecorder(session)
    try await session.send("go")
    let asked = try await recorder.next(\.permissionRequest)
    #expect(asked == request)
    try await session.respond(to: asked, .deny(message: "no"))
    #expect(try await recorder.next(\.turnEnd).text == "deny(message: \"no\")")
    await #expect(throws: AgentError.unknownRequest("p1")) {
      try await session.respond(to: asked, .allowOnce)
    }

    try await session.send("wait")
    _ = try await recorder.next(\.permissionRequest, occurrence: 2)
    await session.interrupt()
    #expect(try await recorder.next(\.turnEnd, occurrence: 2).outcome == .interrupted)
    try await Task.sleep(for: .milliseconds(20))
    #expect(!recorder.events.contains { $0.text?.messageID == "late" })
    let fake = try #require(backend.sessions.first)
    #expect(fake.interrupts == 1)
    #expect(fake.decisions.map(\.decision) == [.deny(message: "no")])
    await session.close()
    try await recorder.finish()
  }

  @Test func startFailure() async {
    let backend = FakeAgentBackend(failure: .executableNotFound("fake"))
    await #expect(throws: AgentError.executableNotFound("fake")) {
      _ = try await backend.startSession(options)
    }
  }
}
