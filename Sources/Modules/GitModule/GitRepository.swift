import Foundation
import Synchronization
import VoCoderCore

/// Git through the `git` CLI (ADR 0011). Repositories are cached by their top-level directory.
public final class GitSourceControl: SourceControl {
  public let id: ProviderID = "git"
  public let displayName = "Git"
  /// nil when git isn't installed: every `repository(at:)` throws `toolMissing`.
  let runner: GitRunner?
  let quiet: Duration
  let maxDelay: Duration
  private let repositories = Mutex<[String: GitRepository]>([:])

  /// `quiet`/`maxDelay` debounce `changes()` (see `DebounceSchedule`).
  public init(
    runner: GitRunner? = GitRunner.findExecutable().map { GitRunner(executable: $0) },
    quiet: Duration = .milliseconds(300), maxDelay: Duration = .seconds(2)
  ) {
    self.runner = runner
    self.quiet = quiet
    self.maxDelay = maxDelay
  }

  public func repository(at directory: URL) async throws -> any Repository {
    guard let runner else { throw SourceControlError.toolMissing("git") }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw SourceControlError.notARepository(directory) }
    let output = try await runner.run(
      ["rev-parse", "--show-toplevel", "--absolute-git-dir"], in: directory,
      operation: "Finding the repository")
    let lines = output.text.split(separator: "\n").map(String.init)
    guard output.status == 0, lines.count == 2 else {
      throw SourceControlError.notARepository(directory)
    }
    let root = Self.realPath(lines[0])
    let gitDir = Self.realPath(lines[1])
    return repositories.withLock { repositories in
      if let existing = repositories[root] { return existing }
      let repository = GitRepository(
        root: URL(filePath: root, directoryHint: .isDirectory), gitDir: gitDir, runner: runner,
        quiet: quiet, maxDelay: maxDelay)
      repositories[root] = repository
      return repository
    }
  }

  /// Symlinks resolved like FSEvents reports them (`/var` → `/private/var`). Foundation's
  /// `resolvingSymlinksInPath` strips `/private` instead, so it won't do.
  static func realPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
  }
}

public final class GitRepository: Repository {
  public let root: URL
  let gitDir: String
  let runner: GitRunner
  private let quiet: Duration
  private let maxDelay: Duration
  private let log = Log(category: "git")

  private struct Watching {
    var streams: [UUID: AsyncStream<Void>.Continuation] = [:]
    var watcher: FileWatcher?
    var debouncer: Debouncer?
    var closed = false
  }

  private let watching = Mutex(Watching())

  init(root: URL, gitDir: String, runner: GitRunner, quiet: Duration, maxDelay: Duration) {
    self.root = root
    self.gitDir = gitDir
    self.runner = runner
    self.quiet = quiet
    self.maxDelay = maxDelay
  }

  deinit { close() }

  // MARK: Reading

  public func status() async throws -> RepoStatus {
    let output = try await git(
      ["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all"],
      operation: "Status")
    return GitParsers.status(output.stdout)
  }

  public func diff(_ path: String?, staged: Bool) async throws -> [FileDiff] {
    let options = [
      "--no-color", "--no-ext-diff", "--no-textconv", "--no-relative", "-M", "--src-prefix=a/",
      "--dst-prefix=b/",
    ]
    if let path, !staged, try await isUntracked(path) {
      // `--no-index` exits 1 when the files differ.
      let output = try await runner.run(
        ["--literal-pathspecs", "diff", "--no-index"] + options + ["--", "/dev/null", path],
        in: root, operation: "Diff")
      guard output.status <= 1 else {
        throw SourceControlError.failed(operation: "Diff", message: GitRunner.message(output))
      }
      return GitParsers.diff(output.text).map { diff in
        var diff = diff
        diff.path = path
        return diff
      }
    }
    var arguments = ["--literal-pathspecs", "diff"] + options
    if staged { arguments.append("--cached") }
    if let path { arguments += ["--", path] }
    return GitParsers.diff(try await git(arguments, operation: "Diff").text)
  }

  private func isUntracked(_ path: String) async throws -> Bool {
    guard FileManager.default.fileExists(atPath: root.appending(path: path).path) else {
      return false
    }
    let output = try await runner.run(
      ["--literal-pathspecs", "ls-files", "--error-unmatch", "--", path], in: root,
      operation: "Diff")
    return output.status != 0
  }

  public func branches() async throws -> [Branch] {
    let output = try await git(
      ["for-each-ref", "--format=\(GitParsers.branchFormat)", "refs/heads"],
      operation: "Listing branches")
    return GitParsers.branches(output.text)
  }

  // MARK: Changing

  public func createBranch(_ name: String, checkout: Bool) async throws {
    let valid = try await runner.run(
      ["check-ref-format", "--branch", name], in: root, operation: "Creating a branch")
    guard valid.status == 0, !name.hasPrefix("-") else {
      throw SourceControlError.invalidBranchName(name)
    }
    guard try await !branchExists(name) else { throw SourceControlError.branchExists(name) }
    let arguments = checkout ? ["switch", "--no-guess", "-c", name] : ["branch", name]
    try await git(arguments, operation: "Creating branch \(name)")
  }

  public func checkout(_ name: String) async throws {
    guard try await branchExists(name) else { throw SourceControlError.unknownBranch(name) }
    try await git(["switch", "--no-guess", name], operation: "Switching to \(name)")
  }

  private func branchExists(_ name: String) async throws -> Bool {
    let output = try await runner.run(
      ["show-ref", "--verify", "--quiet", "refs/heads/\(name)"], in: root,
      operation: "Finding branch \(name)")
    return output.status == 0
  }

  public func stage(_ paths: [String]) async throws {
    try await git(["--literal-pathspecs", "add", "-A", "--"] + paths, operation: "Staging")
  }

  public func commit(message: String) async throws -> CommitID {
    let staged = try await runner.run(
      ["diff", "--cached", "--quiet"], in: root, operation: "Commit")
    guard staged.status != 0 else { throw SourceControlError.nothingToCommit }
    // Hooks may take a while.
    try await git(
      ["commit", "--quiet", "--cleanup=strip", "-m", message], operation: "Commit",
      timeout: .seconds(120))
    let head = try await git(["rev-parse", "HEAD"], operation: "Commit")
    let id = CommitID(head.text.trimmingCharacters(in: .whitespacesAndNewlines))
    log.info("committed \(id.short) in \(root.lastPathComponent)")
    return id
  }

  @discardableResult
  private func git(
    _ arguments: [String], operation: String, timeout: Duration? = nil
  ) async throws -> GitRunner.Output {
    do {
      return try await runner.check(arguments, in: root, operation: operation, timeout: timeout)
    } catch {
      log.error("git \(arguments.first { !$0.hasPrefix("-") } ?? "") failed: \(error)")
      throw error
    }
  }

  // MARK: Watching

  public func changes() -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let key = UUID()
    let added = watching.withLock { watching -> Bool in
      guard !watching.closed else { return false }
      watching.streams[key] = continuation
      if watching.watcher == nil { startWatching(&watching) }
      return true
    }
    guard added else {
      continuation.finish()
      return stream
    }
    continuation.onTermination = { [weak self] _ in self?.removeStream(key) }
    return stream
  }

  public func close() {
    let (streams, watcher) = watching.withLock { watching in
      watching.closed = true
      defer { stopWatching(&watching) }
      defer { watching.streams = [:] }
      return (Array(watching.streams.values), watching.watcher)
    }
    watcher?.stop()
    for stream in streams { stream.finish() }
  }

  private func removeStream(_ key: UUID) {
    let watcher = watching.withLock { watching -> FileWatcher? in
      watching.streams[key] = nil
      guard watching.streams.isEmpty else { return nil }
      defer { stopWatching(&watching) }
      return watching.watcher
    }
    watcher?.stop()
  }

  private func startWatching(_ watching: inout Watching) {
    let debouncer = Debouncer(quiet: quiet, maxDelay: maxDelay) { [weak self] in
      self?.tick()
    }
    let filter = GitPathFilter(root: GitSourceControl.realPath(root.path), gitDir: gitDir)
    let inside = gitDir.hasPrefix(filter.root + "/")
    let watcher = FileWatcher(
      paths: inside ? [filter.root] : [filter.root, gitDir], isRelevant: filter.isRelevant,
      onChange: { debouncer.signal() })
    if !watcher.start() { log.error("can't watch \(root.path)") }
    watching.watcher = watcher
    watching.debouncer = debouncer
  }

  /// Forgets the watcher and debouncer; the caller stops the returned watcher outside the lock.
  private func stopWatching(_ watching: inout Watching) {
    watching.debouncer?.cancel()
    watching.debouncer = nil
    watching.watcher = nil
  }

  private func tick() {
    for stream in watching.withLock({ Array($0.streams.values) }) { stream.yield() }
  }
}
