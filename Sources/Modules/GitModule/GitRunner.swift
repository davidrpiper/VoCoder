import Foundation
import Synchronization
import VoCoderCore

/// Runs `git` in a repository. Foundation `Process` is fine here (no terminal, no job
/// control). The environment is made safe for a background tool: no prompts, pager or editor,
/// no optional index locks (the agent may run git at the same time), and none of the
/// `GIT_DIR`-style variables a parent git hook would leak.
public struct GitRunner: Sendable {
  public struct Output: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String

    public var text: String { String(decoding: stdout, as: UTF8.self) }
  }

  public let executable: URL
  public let environment: [String: String]
  public let timeout: Duration

  /// `overrides` are applied after the safe defaults (tests isolate the user's git config
  /// with them).
  public init(
    executable: URL, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
    overrides: [String: String] = [:], timeout: Duration = .seconds(30)
  ) {
    self.executable = executable
    self.environment = Self.sanitized(baseEnvironment).merging(overrides) { $1 }
    self.timeout = timeout
  }

  /// Variables that point git at another repository, index or work tree.
  static let leakedVariables: Set<String> = [
    "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR",
    "GIT_PREFIX", "GIT_NAMESPACE", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CEILING_DIRECTORIES",
  ]

  static func sanitized(_ environment: [String: String]) -> [String: String] {
    var environment = environment.filter { !leakedVariables.contains($0.key) }
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    environment["GIT_PAGER"] = "cat"
    environment["GIT_EDITOR"] = "true"
    environment["GIT_ASKPASS"] = "true"
    environment["LC_ALL"] = "C"
    return environment
  }

  /// `git` on `PATH`, or in the usual places (`/usr/bin/git` is Xcode's shim).
  public static func findExecutable(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL? {
    let path = (environment["PATH"] ?? "").split(separator: ":").map { URL(filePath: String($0)) }
    let fallbacks = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].map { URL(filePath: $0) }
    return (path + fallbacks).map { $0.appending(path: "git") }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  /// Runs `git <arguments>` in `directory` and returns whatever it exited with. Throws
  /// `toolMissing` when git can't be started and `timedOut` (after killing it).
  public func run(
    _ arguments: [String], in directory: URL?, operation: String, timeout: Duration? = nil
  ) async throws -> Output {
    let timeout = timeout ?? self.timeout
    let process = Process()
    process.executableURL = executable
    // Quoted paths in diff headers keep non-ASCII bytes as-is; parsers unquote the rest.
    process.arguments =
      ["-c", "core.quotePath=false", "-c", "color.ui=false", "-c", "diff.suppressBlankEmpty=false"]
      + arguments
    process.environment = environment
    if let directory { process.currentDirectoryURL = directory }
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    process.standardInput = FileHandle.nullDevice

    let timedOut = Atomic(false)
    let result: Output? = await withCheckedContinuation { continuation in
      let group = DispatchGroup()
      let collected = Mutex<(out: Data, err: Data)>((Data(), Data()))
      group.enter()
      group.enter()
      group.enter()
      process.terminationHandler = { _ in group.leave() }
      do {
        try process.run()
      } catch {
        continuation.resume(returning: nil)
        return
      }
      DispatchQueue.global().async {
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        collected.withLock { $0.out = data }
        group.leave()
      }
      DispatchQueue.global().async {
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        collected.withLock { $0.err = data }
        group.leave()
      }
      let seconds =
        Double(timeout.components.seconds)
        + Double(timeout.components.attoseconds) / 1e18
      let killer = DispatchWorkItem {
        guard process.isRunning else { return }
        timedOut.store(true, ordering: .relaxed)
        process.terminate()
      }
      DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: killer)
      group.notify(queue: .global()) {
        killer.cancel()
        let (out, err) = collected.withLock { ($0.out, $0.err) }
        continuation.resume(
          returning: Output(
            status: process.terminationStatus, stdout: out,
            stderr: String(decoding: err, as: UTF8.self)))
      }
    }
    guard let result else { throw SourceControlError.toolMissing("git") }
    if timedOut.load(ordering: .relaxed) { throw SourceControlError.timedOut(operation: operation) }
    return result
  }

  /// Runs and requires exit status 0; otherwise throws `failed` with git's message.
  @discardableResult
  public func check(
    _ arguments: [String], in directory: URL?, operation: String, timeout: Duration? = nil
  ) async throws -> Output {
    let output = try await run(arguments, in: directory, operation: operation, timeout: timeout)
    guard output.status == 0 else {
      throw SourceControlError.failed(operation: operation, message: Self.message(output))
    }
    return output
  }

  /// git's error, without `fatal:`/`error:` prefixes and hint lines, on one line.
  static func message(_ output: Output) -> String {
    let source = output.stderr.isEmpty ? output.text : output.stderr
    return source.split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix("hint:") }
      .map { line in
        for prefix in ["fatal: ", "error: "] where line.hasPrefix(prefix) {
          return String(line.dropFirst(prefix.count))
        }
        return line
      }
      .joined(separator: " ")
  }
}
