import ClaudeCodeModule
import Foundation
import Synchronization
import Testing
import VoCoderCore
import VoCoderTestSupport

/// The real process plumbing (`ProcessTransport`), with small `sh` scripts standing in for
/// `claude`.
@Suite struct ClaudeProcessTests {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: "vocoder-claude-\(UUID().uuidString)")

  /// Answers `initialize`, then one canned turn per user message. The reply reports the
  /// `--resume` argument and the variables that must (not) reach it. "crash" exits 3.
  static let fakeClaude = #"""
    #!/bin/sh
    echo "fake claude starting" >&2
    resume=none
    previous=
    for argument in "$@"; do
      [ "$previous" = "--resume" ] && resume=$argument
      previous=$argument
    done
    read -r line
    echo '{"type":"control_response","response":{"subtype":"success","request_id":"vc-1","response":{}}}'
    while read -r line; do
      case "$line" in
        *crash*) echo "boom" >&2; exit 3 ;;
        *'"type":"user"'*)
          echo '{"type":"system","subtype":"init","session_id":"s-1","model":"fake","claude_code_version":"2.1.302"}'
          printf '{"type":"assistant","message":{"id":"m","content":[{"type":"text","text":"resume=%s env=%s,%s,%s,%s,%s"}]}}\n' \
            "$resume" "${CLAUDECODE:-unset}" "${CLAUDE_CODE_ENTRYPOINT:-unset}" "${CLAUDE_PID:-unset}" \
            "${AI_AGENT:-unset}" "${CLAUDE_CODE_USE_BEDROCK:-unset}"
          echo '{"type":"result","subtype":"success","is_error":false,"result":"done"}'
          ;;
      esac
    done
    """#

  func script(_ text: String, named name: String = "claude") throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: name)
    try text.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
  }

  func backend(executable: URL, sink: FileLogSink? = nil) -> ClaudeCodeBackend {
    let log = Log(category: "test.claude", sink: sink)
    return ClaudeCodeBackend(
      locate: { executable }, versionOutput: { _ in "2.1.302 (Claude Code)" },
      environment: {
        [
          "PATH": "/usr/bin:/bin", "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli",
          "CLAUDE_PID": "42", "AI_AGENT": "claude-code", "CLAUDE_CODE_USE_BEDROCK": "1",
        ]
      },
      restartDelays: [.zero], launcher: { try ProcessTransport.launch($0, log: log) })
  }

  @Test func turnsEnvironmentAndStderr() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let sink = FileLogSink(directory: directory.appending(path: "logs"))
    let claude = try script(Self.fakeClaude)
    let session = try await backend(executable: claude, sink: sink).startSession(
      AgentSessionOptions(repo: directory))
    let recorder = AgentEventRecorder(session)
    try await session.send("hello")
    _ = try await recorder.next(\.turnEnd)
    #expect(
      recorder.events.compactMap(\.text).map(\.text) == [
        "resume=none env=unset,unset,unset,unset,1"
      ])
    await session.close()
    try await recorder.finish()
    #expect(recorder.events.last == .ended(.closed))
    let log = try String(contentsOf: sink.currentFile, encoding: .utf8)
    #expect(log.contains("stderr: fake claude starting"))
  }

  @Test func crashRestartsTheProcessWithResume() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let claude = try script(Self.fakeClaude)
    let session = try await backend(executable: claude).startSession(
      AgentSessionOptions(repo: directory))
    let recorder = AgentEventRecorder(session)
    try await session.send("hello")
    _ = try await recorder.next(\.turnEnd)
    try await session.send("crash")
    #expect(try await recorder.next(\.error) == .crashed(status: 3, restarting: 1))
    try await session.send("again")
    _ = try await recorder.next(\.turnEnd, occurrence: 2)
    #expect(
      recorder.events.compactMap(\.text).map(\.text).last
        == "resume=s-1 env=unset,unset,unset,unset,1")
    await session.close()
    try await recorder.finish()
  }

  @Test func startupFailureReportsStderr() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let claude = try script("#!/bin/sh\necho 'Not logged in' >&2\nexit 1\n")
    await #expect(throws: AgentError.launchFailed("Not logged in")) {
      _ = try await backend(executable: claude).startSession(AgentSessionOptions(repo: directory))
    }
  }

  @Test func writingToAnExitedProcessThrows() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let launch = ClaudeLaunch(
      executable: URL(filePath: "/bin/sh"), arguments: ["-c", "exit 0"], environment: [:],
      directory: URL(filePath: "/tmp"))
    let transport = try ProcessTransport.launch(launch, log: Log(category: "test", sink: nil))
    #expect(await transport.waitForExit() == 0)
    for await _ in transport.lines {}
    // No SIGPIPE: the write fails instead of killing the test process.
    #expect(throws: AgentError.notRunning) { try transport.write("{}") }
    #expect(await transport.stop() == 0)
  }

  @Test func stopEscalatesToSignals() async throws {
    let launch = ClaudeLaunch(
      executable: URL(filePath: "/bin/sh"), arguments: ["-c", "trap '' TERM; exec sleep 30"],
      environment: [:], directory: URL(filePath: "/tmp"))
    let transport = try ProcessTransport.launch(launch, log: Log(category: "test", sink: nil))
    let status = await transport.stop(grace: .milliseconds(100))
    #expect(status == 128 + SIGKILL)
  }

  @Test func launchFailure() {
    let launch = ClaudeLaunch(
      executable: URL(filePath: "/nonexistent/claude"), arguments: [], environment: [:],
      directory: URL(filePath: "/tmp"))
    #expect(throws: AgentError.self) {
      _ = try ProcessTransport.launch(launch, log: Log(category: "test", sink: nil))
    }
  }
}
