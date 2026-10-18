// Source control contract (ADR 0011): the fake and git (on temporary repositories) both run it.
import Foundation
import Testing
import VoCoderCore

/// Makes repositories in a known state for `SourceControlContract`.
public protocol SourceControlFixture: Sendable {
  /// A new repository: one commit on `main` holding `README.md` = "hello\n", clean.
  func makeRepository() async throws -> URL
  /// Changes a work-tree file like an editor would (nil deletes it).
  func write(_ path: String, _ contents: String?, in root: URL) async throws
  /// A directory that is not inside any repository.
  func makeNonRepository() async throws -> URL
}

public enum SourceControlContract {
  public static func verify(
    _ sourceControl: any SourceControl, fixture: any SourceControlFixture,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    ProviderContract.verify(sourceControl, sourceLocation: sourceLocation)
    #expect(!sourceControl.displayName.isEmpty, sourceLocation: sourceLocation)

    let outside = try await fixture.makeNonRepository()
    await #expect(
      throws: SourceControlError.notARepository(outside), sourceLocation: sourceLocation
    ) {
      _ = try await sourceControl.repository(at: outside)
    }

    let root = try await fixture.makeRepository()
    let repository = try await sourceControl.repository(at: root)
    defer { repository.close() }
    let again = try await sourceControl.repository(at: root)
    #expect(repository === again, "one instance per root", sourceLocation: sourceLocation)

    // A fresh repository is clean on main.
    var status = try await repository.status()
    #expect(status.isClean, "fresh repository: \(status.files)", sourceLocation: sourceLocation)
    #expect(status.branch == "main", sourceLocation: sourceLocation)
    let first = try #require(status.head, sourceLocation: sourceLocation)

    // Edits show up as unstaged, new files as untracked, and both tick `changes()`.
    let changes = repository.changes()
    try await fixture.write("README.md", "hello\nworld\n", in: root)
    try await fixture.write("notes/new file.txt", "new\n", in: root)
    #expect(
      await firstTick(of: changes, within: .seconds(5)), "no change tick after writing",
      sourceLocation: sourceLocation)
    status = try await repository.status()
    #expect(
      status.files == [
        ChangedFile(path: "README.md", unstaged: .modified),
        ChangedFile(path: "notes/new file.txt", isUntracked: true),
      ], sourceLocation: sourceLocation)
    #expect(status.staged.isEmpty, sourceLocation: sourceLocation)

    // Diffs: the work tree against the index; an untracked path as a new file.
    let unstaged = try await repository.diff(nil, staged: false)
    #expect(unstaged.map(\.path) == ["README.md"], sourceLocation: sourceLocation)
    #expect(unstaged.first?.additions == 1 || unstaged.first?.additions == 2)
    #expect(
      unstaged.first?.hunks.flatMap(\.lines).contains {
        $0.kind == .added && $0.text == "world"
      } == true, sourceLocation: sourceLocation)
    let untracked = try await repository.diff("notes/new file.txt", staged: false)
    #expect(untracked.map(\.change) == [.added], sourceLocation: sourceLocation)
    #expect(try await repository.diff(nil, staged: true).isEmpty, sourceLocation: sourceLocation)

    // Nothing staged: commit refuses.
    await #expect(throws: SourceControlError.nothingToCommit, sourceLocation: sourceLocation) {
      _ = try await repository.commit(message: "empty")
    }

    // Stage one file and commit it.
    try await repository.stage(["README.md"])
    status = try await repository.status()
    #expect(status.staged.map(\.path) == ["README.md"], sourceLocation: sourceLocation)
    #expect(
      try await repository.diff("README.md", staged: true).map(\.path) == ["README.md"],
      sourceLocation: sourceLocation)
    let second = try await repository.commit(message: "Say world")
    #expect(second != first, sourceLocation: sourceLocation)
    status = try await repository.status()
    #expect(status.head == second, sourceLocation: sourceLocation)
    #expect(
      status.files == [ChangedFile(path: "notes/new file.txt", isUntracked: true)],
      sourceLocation: sourceLocation)

    // Branches.
    try await repository.createBranch("feature/x", checkout: true)
    #expect(try await repository.status().branch == "feature/x", sourceLocation: sourceLocation)
    let branches = try await repository.branches()
    #expect(branches.map(\.name) == ["feature/x", "main"], sourceLocation: sourceLocation)
    #expect(branches.filter(\.isCurrent).map(\.name) == ["feature/x"])
    #expect(branches.allSatisfy { $0.head == second }, sourceLocation: sourceLocation)
    await #expect(throws: SourceControlError.branchExists("main"), sourceLocation: sourceLocation) {
      try await repository.createBranch("main", checkout: false)
    }
    await #expect(
      throws: SourceControlError.invalidBranchName("bad..name"), sourceLocation: sourceLocation
    ) {
      try await repository.createBranch("bad..name", checkout: false)
    }
    await #expect(throws: SourceControlError.unknownBranch("nope"), sourceLocation: sourceLocation)
    {
      try await repository.checkout("nope")
    }
    try await repository.checkout("main")
    #expect(try await repository.status().branch == "main", sourceLocation: sourceLocation)

    // Stage everything, untracked files included.
    try await fixture.write("README.md", nil, in: root)
    try await repository.stage([])
    status = try await repository.status()
    #expect(
      status.files == [
        ChangedFile(path: "README.md", staged: .deleted),
        ChangedFile(path: "notes/new file.txt", staged: .added),
      ], sourceLocation: sourceLocation)
    _ = try await repository.commit(message: "Move on")
    #expect(try await repository.status().isClean, sourceLocation: sourceLocation)

    // `close()` ends the streams; later ones end at once.
    let open = repository.changes()
    repository.close()
    #expect(await ends(open, within: .seconds(2)), sourceLocation: sourceLocation)
    #expect(await ends(repository.changes(), within: .seconds(2)), sourceLocation: sourceLocation)
  }

  /// Whether `stream` yields within `timeout`.
  public static func firstTick(of stream: AsyncStream<Void>, within timeout: Duration) async
    -> Bool
  {
    await race(timeout) {
      var iterator = stream.makeAsyncIterator()
      return await iterator.next() != nil
    }
  }

  /// Whether `stream` finishes within `timeout` (ticks before the end are skipped).
  public static func ends(_ stream: AsyncStream<Void>, within timeout: Duration) async -> Bool {
    await race(timeout) {
      for await _ in stream {}
      return true
    }
  }

  private static func race(
    _ timeout: Duration, _ body: @escaping @Sendable () async -> Bool
  ) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
      group.addTask { await body() }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
  }
}
