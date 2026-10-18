import Foundation
import Synchronization
import VoCoderCore

/// An in-memory version control system: repositories are file maps (committed tree, index,
/// work tree) with branches, so status, diffs and commits behave like git's for tests, the repo
/// tab's snapshots and `--demo`. Diffs are one whole-file hunk.
public final class FakeSourceControl: SourceControl {
  public let id: ProviderID
  public let displayName = "Fake VCS"
  private let repositories = Mutex<[URL: FakeRepository]>([:])

  public init(id: ProviderID = "fake-vcs") { self.id = id }

  /// Adds a repository at `root` with one commit on `branch` holding `files`.
  @discardableResult
  public func makeRepository(
    at root: URL, branch: String = "main", files: [String: String] = [:]
  ) -> FakeRepository {
    let repository = FakeRepository(root: root, branch: branch, files: files)
    repositories.withLock { $0[root.standardizedFileURL] = repository }
    return repository
  }

  public func repository(at original: URL) async throws -> any Repository {
    let directory = original.standardizedFileURL
    let found = repositories.withLock { repositories in
      repositories.first { root, _ in
        directory.path == root.path || directory.path.hasPrefix(root.path + "/")
      }?.value
    }
    guard let found else { throw SourceControlError.notARepository(original) }
    return found
  }
}

public final class FakeRepository: Repository {
  public let root: URL

  private struct Commit {
    let id: CommitID
    let tree: [String: String]
    let message: String
  }

  private struct State {
    var commits: [CommitID: Commit] = [:]
    /// Branch name → commit.
    var branches: [String: CommitID] = [:]
    var current: String
    var index: [String: String]
    var workTree: [String: String]
    var nextCommit = 1
    var watchers: [UUID: AsyncStream<Void>.Continuation] = [:]
    var closed = false
    var messages: [String] = []
  }

  private let state: Mutex<State>

  init(root: URL, branch: String, files: [String: String]) {
    self.root = root.standardizedFileURL
    var state = State(current: branch, index: files, workTree: files)
    let id = Self.commitID(1)
    state.commits[id] = Commit(id: id, tree: files, message: "Initial commit")
    state.branches[branch] = id
    state.nextCommit = 2
    state.messages = ["Initial commit"]
    self.state = Mutex(state)
  }

  /// Commit messages, oldest first.
  public var commitMessages: [String] { state.withLock { $0.messages } }

  /// Writes a work-tree file (nil deletes it) and ticks `changes()`, like an editor.
  public func write(_ path: String, _ contents: String?) {
    let watchers = state.withLock { state in
      state.workTree[path] = contents
      return Array(state.watchers.values)
    }
    for watcher in watchers { watcher.yield() }
  }

  // MARK: Repository

  public func status() async throws -> RepoStatus {
    state.withLock { state in
      let head = state.branches[state.current]
      let tree = head.flatMap { state.commits[$0]?.tree } ?? [:]
      let paths = Set(tree.keys).union(state.index.keys).union(state.workTree.keys).sorted()
      let files = paths.compactMap { path -> ChangedFile? in
        let committed = tree[path]
        let indexed = state.index[path]
        let working = state.workTree[path]
        if indexed == nil, committed == nil {
          return working == nil ? nil : ChangedFile(path: path, isUntracked: true)
        }
        let staged = Self.change(from: committed, to: indexed)
        let unstaged = Self.change(from: indexed, to: working)
        guard staged != nil || unstaged != nil else { return nil }
        return ChangedFile(path: path, staged: staged, unstaged: unstaged)
      }
      return RepoStatus(branch: state.current, head: head, files: files)
    }
  }

  public func diff(_ path: String?, staged: Bool) async throws -> [FileDiff] {
    state.withLock { state in
      let tree = state.branches[state.current].flatMap { state.commits[$0]?.tree } ?? [:]
      let (old, new) = staged ? (tree, state.index) : (state.index, state.workTree)
      var paths = Set(old.keys).union(new.keys).sorted()
      if let path { paths = paths.filter { $0 == path } }
      var diffs = paths.compactMap { path -> FileDiff? in
        guard let change = Self.change(from: old[path], to: new[path]) else { return nil }
        if !staged, old[path] == nil, tree[path] == nil { return nil }  // untracked
        return Self.fileDiff(path, change: change, old: old[path], new: new[path])
      }
      if !staged, let path, diffs.isEmpty, state.index[path] == nil, tree[path] == nil,
        let contents = state.workTree[path]
      {
        diffs = [Self.fileDiff(path, change: .added, old: nil, new: contents)]
      }
      return diffs
    }
  }

  public func branches() async throws -> [Branch] {
    state.withLock { state in
      state.branches.keys.sorted().map {
        Branch(name: $0, head: state.branches[$0]!, isCurrent: $0 == state.current)
      }
    }
  }

  public func createBranch(_ name: String, checkout: Bool) async throws {
    try state.withLock { state in
      guard Self.isValidBranchName(name) else { throw SourceControlError.invalidBranchName(name) }
      guard state.branches[name] == nil else { throw SourceControlError.branchExists(name) }
      state.branches[name] = state.branches[state.current]
      if checkout { state.current = name }
    }
    tick()
  }

  public func checkout(_ name: String) async throws {
    try state.withLock { state in
      guard let target = state.branches[name], let commit = state.commits[target] else {
        throw SourceControlError.unknownBranch(name)
      }
      let head = state.branches[state.current].flatMap { state.commits[$0]?.tree } ?? [:]
      // Like git: carry local changes over unless they touch files that differ.
      for path in Set(head.keys).union(commit.tree.keys) where head[path] != commit.tree[path] {
        if state.index[path] != head[path] || state.workTree[path] != head[path] {
          throw SourceControlError.failed(
            operation: "Checkout",
            message: "your local changes to \(path) would be overwritten")
        }
      }
      for path in Set(head.keys).union(commit.tree.keys) where head[path] != commit.tree[path] {
        state.index[path] = commit.tree[path]
        state.workTree[path] = commit.tree[path]
      }
      state.current = name
    }
    tick()
  }

  public func stage(_ paths: [String]) async throws {
    state.withLock { state in
      let all = Set(state.index.keys).union(state.workTree.keys)
      for path in paths.isEmpty ? Array(all) : paths {
        state.index[path] = state.workTree[path]
      }
    }
    tick()
  }

  public func commit(message: String) async throws -> CommitID {
    let id = try state.withLock { state in
      let head = state.branches[state.current]
      let tree = head.flatMap { state.commits[$0]?.tree } ?? [:]
      guard state.index != tree else { throw SourceControlError.nothingToCommit }
      let id = Self.commitID(state.nextCommit)
      state.nextCommit += 1
      state.commits[id] = Commit(id: id, tree: state.index, message: message)
      state.branches[state.current] = id
      state.messages.append(message)
      return id
    }
    tick()
    return id
  }

  public func changes() -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let key = UUID()
    let closed = state.withLock { state in
      if !state.closed { state.watchers[key] = continuation }
      return state.closed
    }
    if closed {
      continuation.finish()
    } else {
      continuation.onTermination = { [weak self] _ in
        _ = self?.state.withLock { $0.watchers.removeValue(forKey: key) }
      }
    }
    return stream
  }

  public func close() {
    let watchers = state.withLock { state in
      state.closed = true
      defer { state.watchers = [:] }
      return Array(state.watchers.values)
    }
    for watcher in watchers { watcher.finish() }
  }

  // MARK: Helpers

  private func tick() {
    for watcher in state.withLock({ Array($0.watchers.values) }) { watcher.yield() }
  }

  private static func commitID(_ number: Int) -> CommitID {
    CommitID(String(format: "%07x", number) + String(repeating: "0", count: 33))
  }

  private static func change(from old: String?, to new: String?) -> ChangedFile.Change? {
    switch (old, new) {
    case (nil, nil): nil
    case (nil, _): .added
    case (_, nil): .deleted
    case (let old, let new): old == new ? nil : .modified
    }
  }

  private static func fileDiff(
    _ path: String, change: ChangedFile.Change, old: String?, new: String?
  ) -> FileDiff {
    let oldLines = old.map(lines) ?? []
    let newLines = new.map(lines) ?? []
    var diffLines = oldLines.enumerated().map {
      DiffLine(kind: .removed, text: $1, oldLine: $0 + 1)
    }
    diffLines += newLines.enumerated().map { DiffLine(kind: .added, text: $1, newLine: $0 + 1) }
    let hunk = DiffHunk(
      oldStart: oldLines.isEmpty ? 0 : 1, oldCount: oldLines.count,
      newStart: newLines.isEmpty ? 0 : 1, newCount: newLines.count, lines: diffLines)
    return FileDiff(path: path, change: change, hunks: diffLines.isEmpty ? [] : [hunk])
  }

  private static func lines(_ text: String) -> [String] {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if lines.last == "" { lines.removeLast() }
    return lines
  }

  /// A subset of git's rules: no spaces, `..`, leading `-`, trailing `/` or `.lock`.
  static func isValidBranchName(_ name: String) -> Bool {
    !name.isEmpty && !name.contains { $0.isWhitespace || "~^:?*[\\".contains($0) }
      && !name.contains("..") && !name.hasPrefix("-") && !name.hasSuffix("/")
      && !name.hasSuffix(".lock") && !name.contains("@{")
  }
}
