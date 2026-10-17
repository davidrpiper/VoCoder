import ClaudeCodeModule
import Foundation
import Testing
import VoCoderCore
import VoCoderTestSupport

/// Real Claude Code (Haiku) in a throwaway git repo: an approved tool call, `<spoken>`, an
/// interrupt and a resume. Opt-in (`VOCODER_LIVE_CLAUDE=1 make test`): needs `claude` logged in
/// and uses a little of the account's quota.
@Suite(
  .enabled(if: ProcessInfo.processInfo.environment["VOCODER_LIVE_CLAUDE"] == "1"),
  .timeLimit(.minutes(5))
)
struct ClaudeLiveTests {
  @Test func approvedToolCallInterruptAndResume() async throws {
    let repo = FileManager.default.temporaryDirectory
      .appending(path: "vocoder-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: repo) }
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try run("/usr/bin/git", "init", "-q", in: repo)
    let backend = ClaudeCodeBackend(config: ClaudeCodeConfig(model: "haiku"))
    let timeout = Duration.seconds(120)

    let session = try await backend.startSession(AgentSessionOptions(repo: repo))
    let recorder = AgentEventRecorder(session)
    try await session.send("Use the Write tool to create hello.txt containing exactly: hi")
    let request = try await recorder.next(\.permissionRequest, timeout: timeout)
    #expect(request.toolName == "Write")
    try await session.respond(to: request, .allowForSession)
    let first = try await recorder.next(\.turnEnd, timeout: timeout)
    #expect(first.outcome == .completed)
    let written = try String(contentsOf: repo.appending(path: "hello.txt"), encoding: .utf8)
    #expect(written.trimmingCharacters(in: .whitespacesAndNewlines) == "hi")
    let info = try #require(recorder.events.compactMap(\.sessionStarted).first)
    let version = try #require(info.agentVersion.flatMap { CLIVersion($0) })
    #expect(version >= ClaudeCodeModule.minimumCLIVersion)
    #expect(!recorder.events.compactMap(\.spokenSummary).isEmpty)

    let streamed = recorder.events.compactMap(\.textDelta).count
    try await session.send("Write a 400 word story about a lighthouse. No tools.")
    _ = try await recorder.next(\.textDelta, occurrence: streamed + 1, timeout: timeout)
    await session.interrupt()
    let second = try await recorder.next(\.turnEnd, occurrence: 2, timeout: timeout)
    #expect(second.outcome == .interrupted, "\(second)")
    await session.close()
    try await recorder.finish()
    #expect(recorder.events.compactMap(\.error).isEmpty)

    let resumed = try await backend.startSession(AgentSessionOptions(repo: repo, resume: info.id))
    let resumedRecorder = AgentEventRecorder(resumed)
    try await resumed.send("Which file did you create earlier? Reply with just the file name.")
    #expect(try await resumedRecorder.next(\.turnEnd, timeout: timeout).outcome == .completed)
    #expect(resumedRecorder.events.compactMap(\.sessionStarted).map(\.id) == [info.id])
    let reply = resumedRecorder.events.compactMap(\.text).map(\.text).joined()
    #expect(reply.contains("hello.txt"))
    await resumed.close()
  }

  private func run(_ executable: String, _ arguments: String..., in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    try process.run()
    process.waitUntilExit()
  }
}
