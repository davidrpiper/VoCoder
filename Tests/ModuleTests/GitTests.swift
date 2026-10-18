import Foundation
import GitModule
import Synchronization
import Testing
import VoCoderCore
import VoCoderFakes
import VoCoderTestSupport

/// Git against temporary repositories (isolated from the user's git config).
@Suite struct GitTests {
  @Test func contract() async throws {
    let fixture = try GitFixture()
    try await SourceControlContract.verify(fixture.sourceControl(), fixture: fixture)
  }

  @Test func gitMissing() async throws {
    let fixture = try GitFixture()
    let root = try await fixture.makeRepository()
    await #expect(throws: SourceControlError.toolMissing("git")) {
      _ = try await GitSourceControl(runner: nil).repository(at: root)
    }
  }

  @Test func subdirectoriesOpenTheirRepository() async throws {
    let fixture = try GitFixture()
    let root = try await fixture.makeRepository(files: ["src/a.txt": "a\n"])
    let sourceControl = fixture.sourceControl()
    let repository = try await sourceControl.repository(at: root.appending(path: "src"))
    #expect(try await sourceControl.repository(at: root) === repository)
    #expect(repository.root.lastPathComponent == root.lastPathComponent)
  }

  @Test func unbornRepository() async throws {
    let fixture = try GitFixture()
    let root = try await fixture.makeRepository(files: [:])
    let repository = try await fixture.sourceControl().repository(at: root)
    var status = try await repository.status()
    #expect(status.head == nil && status.branch == "main" && status.isClean)
    try await fixture.write("first.txt", "1\n", in: root)
    try await repository.stage([])
    #expect(try await repository.diff(nil, staged: true).map(\.change) == [.added])
    let id = try await repository.commit(message: "First")
    status = try await repository.status()
    #expect(status.head == id)
    #expect(try await repository.branches().map(\.name) == ["main"])
  }

  @Test func renamesUpstreamAndDetachedHead() async throws {
    let fixture = try GitFixture()
    let origin = try await fixture.makeRepository(files: ["old.txt": "a\nb\nc\n"])
    let clone = fixture.base.appending(path: "clone", directoryHint: .isDirectory)
    try await fixture.git(["clone", "--quiet", origin.path, clone.path], in: fixture.base)
    let repository = try await fixture.sourceControl().repository(at: clone)

    try await fixture.git(["mv", "old.txt", "new.txt"], in: clone)
    var status = try await repository.status()
    #expect(status.upstream == "origin/main")
    #expect(
      status.files == [ChangedFile(path: "new.txt", originalPath: "old.txt", staged: .renamed)])
    let diff = try await repository.diff(nil, staged: true)
    #expect(diff == [FileDiff(path: "new.txt", originalPath: "old.txt", change: .renamed)])

    _ = try await repository.commit(message: "Rename")
    status = try await repository.status()
    #expect((status.ahead, status.behind) == (1, 0))
    #expect(try await repository.branches().first?.upstream == "origin/main")

    try await fixture.git(["switch", "--quiet", "--detach", "HEAD~1"], in: clone)
    status = try await repository.status()
    #expect(status.isDetached)
    #expect(try await repository.branches().allSatisfy { !$0.isCurrent })
  }

  @Test func conflicts() async throws {
    let fixture = try GitFixture()
    let root = try await fixture.makeRepository(files: ["a.txt": "base\n"])
    let repository = try await fixture.sourceControl().repository(at: root)
    try await repository.createBranch("other", checkout: true)
    try await fixture.write("a.txt", "other\n", in: root)
    try await repository.stage([])
    _ = try await repository.commit(message: "Other")
    try await repository.checkout("main")
    try await fixture.write("a.txt", "main\n", in: root)
    try await repository.stage([])
    _ = try await repository.commit(message: "Main")
    _ = try await fixture.runner.run(["merge", "other"], in: root, operation: "merge")
    let status = try await repository.status()
    #expect(status.conflicted.map(\.path) == ["a.txt"])
  }

  @Test func checkoutKeepsLocalChangesSafe() async throws {
    let fixture = try GitFixture()
    let root = try await fixture.makeRepository(files: ["a.txt": "one\n"])
    let repository = try await fixture.sourceControl().repository(at: root)
    try await repository.createBranch("other", checkout: true)
    try await fixture.write("a.txt", "two\n", in: root)
    try await repository.stage([])
    _ = try await repository.commit(message: "Two")
    try await fixture.write("a.txt", "local\n", in: root)
    do {
      try await repository.checkout("main")
      Issue.record("checkout overwrote local changes")
    } catch SourceControlError.failed(_, let message) {
      #expect(message.contains("would be overwritten"))
    }
    #expect(try await repository.status().branch == "other")
    #expect(try String(contentsOf: root.appending(path: "a.txt"), encoding: .utf8) == "local\n")
  }

  @Test func failingHookReportsItsMessage() async throws {
    let fixture = try GitFixture()
    let root = try await fixture.makeRepository()
    let hook = root.appending(path: ".git/hooks/pre-commit")
    try Data("#!/bin/sh\necho 'lint failed: x.swift' >&2\nexit 1\n".utf8).write(to: hook)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
    let repository = try await fixture.sourceControl().repository(at: root)
    try await fixture.write("x.swift", "x\n", in: root)
    try await repository.stage(["x.swift"])
    await #expect(
      throws: SourceControlError.failed(operation: "Commit", message: "lint failed: x.swift")
    ) {
      _ = try await repository.commit(message: "X")
    }
  }

  @Test func pathsAreLiteral() async throws {
    let fixture = try GitFixture()
    let root = try await fixture.makeRepository()
    let repository = try await fixture.sourceControl().repository(at: root)
    try await fixture.write("*.txt", "star\n", in: root)
    try await fixture.write("b.txt", "b\n", in: root)
    try await repository.stage(["*.txt"])
    #expect(try await repository.status().staged.map(\.path) == ["*.txt"])
    #expect(try await repository.diff("b.txt", staged: false).map(\.change) == [.added])
  }

  @Test func watcherCoalescesBurstsAndIgnoresGitInternals() async throws {
    let fixture = try GitFixture()
    let root = try await fixture.makeRepository()
    let repository =
      try await fixture
      .sourceControl(quiet: .milliseconds(150), maxDelay: .seconds(5)).repository(at: root)
    defer { repository.close() }
    let ticks = TickCounter(repository.changes())
    try await Task.sleep(for: .milliseconds(300))
    let settled = ticks.count

    // Objects, logs and lock files don't tick.
    try await fixture.write(".git/objects/zz/junk", "x", in: root)
    try await fixture.write(".git/index.lock", "x", in: root)
    try await fixture.write(".git/logs/HEAD", "x", in: root)
    try await Task.sleep(for: .milliseconds(600))
    #expect(ticks.count == settled)

    // A burst of writes is one tick.
    for index in 0..<20 { try await fixture.write("f\(index).txt", "\(index)\n", in: root) }
    #expect(await ticks.wait(for: settled + 1))
    try await Task.sleep(for: .milliseconds(500))
    #expect(ticks.count == settled + 1)

    // A ref change made by git ticks.
    try await fixture.git(["branch", "side"], in: root)
    #expect(await ticks.wait(for: settled + 2))
  }

  @Test func doctorCheck() async throws {
    let minimum = GitModule.minimumGitVersion
    let git = URL(filePath: "/usr/bin/git")
    func check(found: Bool = true, output: String?) -> GitCLICheck {
      GitCLICheck(minimum: minimum, locate: { found ? git : nil }, versionOutput: { _ in output })
    }
    #expect(
      await check(output: "git version 2.50.1 (Apple Git-155)\n").run()
        == .ok("2.50.1 at /usr/bin/git"))
    #expect(await check(output: "git version 2.20.0").run().status == .failure)
    #expect(await check(found: false, output: nil).run().status == .failure)
    #expect(await check(output: nil).run().status == .failure)
    // The real one, on this Mac.
    let real = await GitCLICheck(minimum: minimum).run()
    #expect(real.status == .ok, "\(real)")
    await DoctorCheckContract.verify(GitCLICheck(minimum: minimum))
  }
}

/// Counts a stream's ticks in the background.
final class TickCounter: Sendable {
  private let counted = Mutex(0)

  init(_ stream: AsyncStream<Void>) {
    Task {
      for await _ in stream { self.counted.withLock { $0 += 1 } }
    }
  }

  var count: Int { counted.withLock { $0 } }

  /// Waits until at least `count` ticks arrived (up to 5 s).
  func wait(for count: Int) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while self.count < count {
      guard ContinuousClock.now < deadline else { return false }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return true
  }
}
