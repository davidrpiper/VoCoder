import Foundation
import Synchronization
import VoCoderCore

/// The pipe to one `claude` process: NDJSON lines both ways. `ProcessTransport` runs the real
/// CLI; tests replay recorded transcripts through the same seam (ADR 0010).
public protocol ClaudeTransport: Sendable {
  /// stdout, one element per line (without the newline). Finishes when stdout closes.
  var lines: AsyncStream<String> { get }
  /// Writes `line` plus a newline to stdin. Throws when the process is gone.
  func write(_ line: String) throws
  /// Closes stdin; the CLI exits at end of input.
  func closeInput()
  func signal(_ signal: Int32)
  /// The exit status (128 + n for signal n), once the process has exited.
  func waitForExit() async -> Int32
  /// The last lines the process wrote to stderr, for error messages.
  var recentErrorOutput: String { get }
}

extension ClaudeTransport {
  /// Ends the process: end of input, then SIGTERM, then SIGKILL, `grace` apart.
  public func stop(grace: Duration = .seconds(2)) async -> Int32 {
    closeInput()
    if let status = await exitStatus(within: grace) { return status }
    signal(SIGTERM)
    if let status = await exitStatus(within: grace) { return status }
    signal(SIGKILL)
    return await waitForExit()
  }

  /// The exit status, or nil if the process is still running after `timeout`.
  private func exitStatus(within timeout: Duration) async -> Int32? {
    let first = FirstResult<Int32?>()
    Task { first.offer(await waitForExit()) }
    Task {
      try? await Task.sleep(for: timeout)
      first.offer(nil)
    }
    return await first.value
  }
}

/// The first value offered wins; later offers are ignored. (A task group would wait for the
/// losing, uncancellable `waitForExit`.)
private final class FirstResult<Value: Sendable>: Sendable {
  private let state = Mutex<(value: Value?, waiters: [CheckedContinuation<Value, Never>])>(
    (nil, []))

  func offer(_ value: Value) {
    let waiters = state.withLock { state -> [CheckedContinuation<Value, Never>] in
      guard state.value == nil else { return [] }
      state.value = value
      defer { state.waiters.removeAll() }
      return state.waiters
    }
    for waiter in waiters { waiter.resume(returning: value) }
  }

  var value: Value {
    get async {
      await withCheckedContinuation { waiter in
        let value = state.withLock { state in
          if state.value == nil { state.waiters.append(waiter) }
          return state.value
        }
        if let value { waiter.resume(returning: value) }
      }
    }
  }
}

/// Starts a transport for a launch description; replaced in tests.
public typealias ClaudeLauncher = @Sendable (ClaudeLaunch) throws -> any ClaudeTransport

/// A real `claude` child process. stderr goes to the log. Foundation `Process` puts the child
/// in its own process group, which suits a headless agent (it exits when stdin closes, also
/// when VoCoder dies).
public final class ProcessTransport: ClaudeTransport {
  public let lines: AsyncStream<String>
  private let linesContinuation: AsyncStream<String>.Continuation
  private let process: Process
  private let input: FileHandle
  private let state = Mutex(State())
  private let log: Log

  private struct State {
    var stdoutBuffer = Data()
    var stderrBuffer = Data()
    var recentErrors: [String] = []
    var exitStatus: Int32?
    var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    var inputClosed = false
  }

  /// Spawns the process. Throws `AgentError.launchFailed` when it can't start.
  public static func launch(_ launch: ClaudeLaunch, log: Log) throws -> ProcessTransport {
    try ProcessTransport(launch, log: log)
  }

  private init(_ launch: ClaudeLaunch, log: Log) throws {
    self.log = log
    (lines, linesContinuation) = AsyncStream.makeStream()
    process = Process()
    process.executableURL = launch.executable
    process.arguments = launch.arguments
    process.environment = launch.environment
    process.currentDirectoryURL = launch.directory
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    input = stdin.fileHandleForWriting
    // A write after the child died must fail with EPIPE, not kill VoCoder with SIGPIPE.
    _ = fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1)

    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.receiveStdout(handle)
    }
    stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.receiveStderr(handle)
    }
    process.terminationHandler = { [weak self] process in
      let status =
        process.terminationReason == .uncaughtSignal
        ? 128 + process.terminationStatus : process.terminationStatus
      self?.exited(status)
    }
    do {
      try process.run()
    } catch {
      stdout.fileHandleForReading.readabilityHandler = nil
      stderr.fileHandleForReading.readabilityHandler = nil
      throw AgentError.launchFailed("\(launch.executable.path): \(error.localizedDescription)")
    }
    log.info("started \(launch.executable.lastPathComponent) pid \(process.processIdentifier)")
  }

  public func write(_ line: String) throws {
    let closed = state.withLock { $0.inputClosed }
    guard !closed else { throw AgentError.notRunning }
    do {
      try input.write(contentsOf: Data((line + "\n").utf8))
    } catch {
      throw AgentError.notRunning
    }
  }

  public func closeInput() {
    let alreadyClosed = state.withLock { state in
      defer { state.inputClosed = true }
      return state.inputClosed
    }
    if !alreadyClosed { try? input.close() }
  }

  public func signal(_ signal: Int32) {
    guard process.isRunning else { return }
    kill(process.processIdentifier, signal)
  }

  public func waitForExit() async -> Int32 {
    await withCheckedContinuation { continuation in
      let status = state.withLock { state in
        if state.exitStatus == nil { state.exitWaiters.append(continuation) }
        return state.exitStatus
      }
      if let status { continuation.resume(returning: status) }
    }
  }

  public var recentErrorOutput: String {
    state.withLock { $0.recentErrors.joined(separator: "\n") }
  }

  private func receiveStdout(_ handle: FileHandle) {
    let data = handle.availableData
    guard !data.isEmpty else {
      handle.readabilityHandler = nil
      let rest = state.withLock { state in
        defer { state.stdoutBuffer.removeAll() }
        return state.stdoutBuffer
      }
      if !rest.isEmpty { linesContinuation.yield(String(decoding: rest, as: UTF8.self)) }
      linesContinuation.finish()
      return
    }
    for line in state.withLock({ Self.takeLines(from: &$0.stdoutBuffer, adding: data) }) {
      linesContinuation.yield(line)
    }
  }

  private func receiveStderr(_ handle: FileHandle) {
    let data = handle.availableData
    guard !data.isEmpty else {
      handle.readabilityHandler = nil
      return
    }
    let lines = state.withLock { state in
      let lines = Self.takeLines(from: &state.stderrBuffer, adding: data)
      state.recentErrors = Array((state.recentErrors + lines).suffix(20))
      return lines
    }
    for line in lines { log.notice("stderr: \(line)") }
  }

  private func exited(_ status: Int32) {
    let waiters = state.withLock { state in
      state.exitStatus = status
      defer { state.exitWaiters.removeAll() }
      return state.exitWaiters
    }
    log.info("pid \(process.processIdentifier) exited with status \(status)")
    for waiter in waiters { waiter.resume(returning: status) }
  }

  /// Complete lines in `buffer` + `data`; the incomplete rest stays in `buffer`.
  private static func takeLines(from buffer: inout Data, adding data: Data) -> [String] {
    buffer.append(data)
    var lines: [String] = []
    while let newline = buffer.firstIndex(of: 0x0A) {
      var line = buffer[buffer.startIndex..<newline]
      if line.last == 0x0D { line = line.dropLast() }
      lines.append(String(decoding: line, as: UTF8.self))
      buffer.removeSubrange(buffer.startIndex...newline)
    }
    return lines
  }
}
