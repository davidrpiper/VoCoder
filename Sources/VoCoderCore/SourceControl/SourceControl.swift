import Foundation

// Source control for repo tabs (DESIGN §3.2, ADR 0011). Git is the only adapter (`GitModule`);
// the seam exists so the repo tab and workflows reach it without importing a module, and it is
// shaped by git (index, branches), not generalised for other systems.

/// A version-control system that opens repositories (git).
public protocol SourceControl: Provider {
  /// Shown and spoken ("Git").
  var displayName: String { get }
  /// The repository containing `directory`. Returns the same instance for the same root, so
  /// the repo tab and commands share one watcher. Throws `SourceControlError.notARepository`
  /// or `.toolMissing`.
  func repository(at directory: URL) async throws -> any Repository
}

/// One repository's work tree, index and branches.
public protocol Repository: AnyObject, Sendable {
  /// The top of the work tree.
  var root: URL { get }
  func status() async throws -> RepoStatus
  /// Changes of `path` (nil: all files). `staged` compares the index with HEAD, otherwise the
  /// work tree with the index; an untracked `path` diffs as a new file.
  func diff(_ path: String?, staged: Bool) async throws -> [FileDiff]
  /// Local branches, sorted by name.
  func branches() async throws -> [Branch]
  /// Creates `name` at HEAD; `checkout` also switches to it.
  func createBranch(_ name: String, checkout: Bool) async throws
  /// Switches to the local branch `name`. Fails (and changes nothing) when local changes would
  /// be overwritten.
  func checkout(_ name: String) async throws
  /// Stages `paths` (relative to `root`); empty stages every change, untracked files included.
  func stage(_ paths: [String]) async throws
  /// Commits the index. Throws `.nothingToCommit` when nothing is staged.
  func commit(message: String) async throws -> CommitID
  /// Ticks after files in the work tree, the index, HEAD or refs changed (debounced). Every call
  /// returns a new stream; each ends when the caller stops iterating or at `close()`.
  func changes() -> AsyncStream<Void>
  /// Ends every `changes()` stream and stops watching. Idempotent.
  func close()
}

/// A commit hash.
public struct CommitID: RawRepresentable, Hashable, Sendable, CustomStringConvertible,
  ExpressibleByStringLiteral
{
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }

  /// The first 7 characters, as shown and spoken.
  public var short: String { String(rawValue.prefix(7)) }
  public var description: String { rawValue }
}

/// The work tree's state.
public struct RepoStatus: Sendable, Equatable {
  /// The checked-out branch; nil when HEAD is detached.
  public var branch: String?
  /// nil before the first commit.
  public var head: CommitID?
  /// The upstream branch (`origin/main`), if any.
  public var upstream: String?
  /// Commits ahead of / behind the upstream (0 without one).
  public var ahead: Int
  public var behind: Int
  /// Changed, untracked and conflicted files, in path order.
  public var files: [ChangedFile]

  public init(
    branch: String? = nil, head: CommitID? = nil, upstream: String? = nil, ahead: Int = 0,
    behind: Int = 0, files: [ChangedFile] = []
  ) {
    self.branch = branch
    self.head = head
    self.upstream = upstream
    self.ahead = ahead
    self.behind = behind
    self.files = files
  }

  public var isClean: Bool { files.isEmpty }
  public var isDetached: Bool { branch == nil }
  /// Files with staged changes.
  public var staged: [ChangedFile] { files.filter { $0.staged != nil } }
  public var conflicted: [ChangedFile] { files.filter(\.isConflicted) }

  /// "main, 3 changed files", "main, clean", "detached at abc1234, 1 changed file".
  public var summary: String {
    let place =
      branch ?? head.map { "detached at \($0.short)" } ?? "detached HEAD"
    guard !isClean else { return "\(place), clean" }
    return "\(place), \(files.count) changed \(files.count == 1 ? "file" : "files")"
  }
}

/// One file in `RepoStatus`.
public struct ChangedFile: Sendable, Equatable, Identifiable {
  public enum Change: Sendable, Equatable {
    case added, modified, deleted, renamed, copied, typeChanged
  }

  /// Relative to the root, `/`-separated.
  public var path: String
  /// The path before a rename or copy.
  public var originalPath: String?
  /// Index vs HEAD.
  public var staged: Change?
  /// Work tree vs index.
  public var unstaged: Change?
  public var isUntracked: Bool
  /// Unmerged (a merge or rebase conflict).
  public var isConflicted: Bool

  public init(
    path: String, originalPath: String? = nil, staged: Change? = nil, unstaged: Change? = nil,
    isUntracked: Bool = false, isConflicted: Bool = false
  ) {
    self.path = path
    self.originalPath = originalPath
    self.staged = staged
    self.unstaged = unstaged
    self.isUntracked = isUntracked
    self.isConflicted = isConflicted
  }

  public var id: String { path }
}

/// A local branch.
public struct Branch: Sendable, Equatable, Identifiable {
  public var name: String
  public var head: CommitID
  public var upstream: String?
  public var isCurrent: Bool

  public init(name: String, head: CommitID, upstream: String? = nil, isCurrent: Bool = false) {
    self.name = name
    self.head = head
    self.upstream = upstream
    self.isCurrent = isCurrent
  }

  public var id: String { name }
}

/// One file's changes.
public struct FileDiff: Sendable, Equatable, Identifiable {
  public var path: String
  public var originalPath: String?
  public var change: ChangedFile.Change
  /// Binary files have no hunks.
  public var isBinary: Bool
  public var hunks: [DiffHunk]

  public init(
    path: String, originalPath: String? = nil, change: ChangedFile.Change = .modified,
    isBinary: Bool = false, hunks: [DiffHunk] = []
  ) {
    self.path = path
    self.originalPath = originalPath
    self.change = change
    self.isBinary = isBinary
    self.hunks = hunks
  }

  public var id: String { path }
  public var additions: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .added } } }
  public var deletions: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .removed } } }
}

/// A run of changed lines with context (`@@ -oldStart,oldCount +newStart,newCount @@`).
public struct DiffHunk: Sendable, Equatable {
  public var oldStart: Int
  public var oldCount: Int
  public var newStart: Int
  public var newCount: Int
  /// The text after the closing `@@` (often the enclosing function).
  public var section: String
  public var lines: [DiffLine]

  public init(
    oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, section: String = "",
    lines: [DiffLine] = []
  ) {
    self.oldStart = oldStart
    self.oldCount = oldCount
    self.newStart = newStart
    self.newCount = newCount
    self.section = section
    self.lines = lines
  }
}

public struct DiffLine: Sendable, Equatable {
  public enum Kind: Sendable, Equatable { case context, added, removed }

  public var kind: Kind
  /// Without the leading marker and line break.
  public var text: String
  /// Line numbers in the old and new file (nil for added / removed lines respectively).
  public var oldLine: Int?
  public var newLine: Int?
  /// The file doesn't end with a line break after this line.
  public var noNewlineAtEnd: Bool

  public init(
    kind: Kind, text: String, oldLine: Int? = nil, newLine: Int? = nil,
    noNewlineAtEnd: Bool = false
  ) {
    self.kind = kind
    self.text = text
    self.oldLine = oldLine
    self.newLine = newLine
    self.noNewlineAtEnd = noNewlineAtEnd
  }
}

public enum SourceControlError: Error, Equatable, CustomStringConvertible {
  /// The tool (`git`) isn't installed.
  case toolMissing(String)
  case notARepository(URL)
  case nothingToCommit
  case invalidBranchName(String)
  case branchExists(String)
  case unknownBranch(String)
  /// The tool failed; `message` is its error output.
  case failed(operation: String, message: String)
  case timedOut(operation: String)

  public var description: String {
    switch self {
    case .toolMissing(let tool): "\(tool) isn't installed"
    case .notARepository(let url): "\(url.path) isn't a repository"
    case .nothingToCommit: "Nothing to commit"
    case .invalidBranchName(let name): "'\(name)' isn't a valid branch name"
    case .branchExists(let name): "Branch \(name) already exists"
    case .unknownBranch(let name): "No branch named \(name)"
    case .failed(let operation, let message):
      message.isEmpty ? "\(operation) failed" : "\(operation) failed: \(message)"
    case .timedOut(let operation): "\(operation) timed out"
    }
  }
}
