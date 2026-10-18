import Foundation
import GitModule
import VoCoderCore
import VoCoderTestSupport

/// Temporary git repositories for tests, isolated from the user's and the system's git config.
/// Everything lives under one temporary directory, removed on `deinit`.
final class GitFixture: SourceControlFixture {
  let base: URL
  let runner: GitRunner

  init() throws {
    base = FileManager.default.temporaryDirectory
      .appending(path: "vocoder-git-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    guard let git = GitRunner.findExecutable() else { throw SourceControlError.toolMissing("git") }
    runner = GitRunner(executable: git, overrides: Self.environment)
  }

  deinit { try? FileManager.default.removeItem(at: base) }

  static let environment = [
    "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
    "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
  ]

  /// A source control over this fixture's isolated git, with short debounce times.
  func sourceControl(
    quiet: Duration = .milliseconds(50), maxDelay: Duration = .milliseconds(500)
  ) -> GitSourceControl {
    GitSourceControl(runner: runner, quiet: quiet, maxDelay: maxDelay)
  }

  // MARK: SourceControlFixture

  func makeRepository() async throws -> URL {
    try await makeRepository(files: ["README.md": "hello\n"])
  }

  func write(_ path: String, _ contents: String?, in root: URL) async throws {
    let url = root.appending(path: path)
    guard let contents else {
      try FileManager.default.removeItem(at: url)
      return
    }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url)
  }

  func makeNonRepository() async throws -> URL {
    let url = base.appending(path: "plain-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  // MARK: Helpers

  /// A repository with one commit on `main` holding `files` (none: an unborn `main`).
  func makeRepository(name: String? = nil, files: [String: String]) async throws -> URL {
    let root = base.appending(
      path: name ?? "repo-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try await git(["init", "--quiet", "-b", "main"], in: root)
    guard !files.isEmpty else { return root }
    for (path, contents) in files { try await write(path, contents, in: root) }
    try await git(["add", "-A"], in: root)
    try await git(["commit", "--quiet", "-m", "Initial commit"], in: root)
    return root
  }

  @discardableResult
  func git(_ arguments: [String], in root: URL) async throws -> String {
    try await runner.check(arguments, in: root, operation: "git \(arguments[0])").text
  }
}
