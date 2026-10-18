import Foundation
import Testing
import VoCoderCore

@testable import GitModule

/// The parsers on output recorded from git 2.56 (renames, binary files, missing final newlines,
/// paths with spaces, tabs and non-ASCII characters).
@Suite struct GitParserTests {
  @Test func status() {
    let fields = [
      "# branch.oid 5ddbac9d1bf3b5902ce35644432017a1fa07758c",
      "# branch.head main",
      "# branch.upstream origin/main",
      "# branch.ab +2 -1",
      "1 .M N... 100644 100644 100644 bdc955b bdc955b bin.dat",
      "2 R. N... 100644 100644 100644 de98044 de98044 R100 new.txt", "old.txt",
      "1 MM N... 100644 100644 100644 c1b0730 1b32298 nonl.txt",
      "1 .M N... 100644 100644 100644 45b983b 45b983b sp ace.txt",
      "u UU N... 100644 100644 100644 100644 aaaaaaa bbbbbbb ccccccc merge me.txt",
      "1 D. N... 100644 000000 000000 abcdef0 0000000 gone.txt",
      "? t\tb.txt",
      "? é.txt",
      "",
    ]
    let status = GitParsers.status(Data(fields.joined(separator: "\0").utf8))
    #expect(status.branch == "main")
    #expect(status.head == "5ddbac9d1bf3b5902ce35644432017a1fa07758c")
    #expect(status.upstream == "origin/main")
    #expect((status.ahead, status.behind) == (2, 1))
    #expect(
      status.files == [
        ChangedFile(path: "bin.dat", unstaged: .modified),
        ChangedFile(path: "gone.txt", staged: .deleted),
        ChangedFile(path: "merge me.txt", isConflicted: true),
        ChangedFile(path: "new.txt", originalPath: "old.txt", staged: .renamed),
        ChangedFile(path: "nonl.txt", staged: .modified, unstaged: .modified),
        ChangedFile(path: "sp ace.txt", unstaged: .modified),
        ChangedFile(path: "t\tb.txt", isUntracked: true),
        ChangedFile(path: "é.txt", isUntracked: true),
      ])
    #expect(status.summary == "main, 8 changed files")
  }

  @Test func statusOfAnUnbornAndADetachedHead() {
    let unborn = GitParsers.status(Data("# branch.oid (initial)\0# branch.head main\0".utf8))
    #expect(unborn.head == nil)
    #expect(unborn.branch == "main")
    #expect(unborn.summary == "main, clean")

    let detached = GitParsers.status(
      Data("# branch.oid 5ddbac9d1bf3b590\0# branch.head (detached)\0? x\0".utf8))
    #expect(detached.isDetached)
    #expect(detached.summary == "detached at 5ddbac9, 1 changed file")
  }

  @Test func branches() {
    let text = """
      main\05ddbac9\0origin/main\0*
      feature/x\01234567\0\0\u{20}

      """
    #expect(
      GitParsers.branches(text) == [
        Branch(name: "feature/x", head: "1234567"),
        Branch(name: "main", head: "5ddbac9", upstream: "origin/main", isCurrent: true),
      ])
  }

  @Test func diffOfARenameAndMissingFinalNewlines() {
    let text = """
      diff --git a/old.txt b/new.txt
      similarity index 100%
      rename from old.txt
      rename to new.txt
      diff --git a/nonl.txt b/nonl.txt
      index c1b0730..1b32298 100644
      --- a/nonl.txt
      +++ b/nonl.txt
      @@ -1 +1,2 @@ func f() {
      -x
      \\ No newline at end of file
      +x
      +y
      \\ No newline at end of file

      """
    let diffs = GitParsers.diff(text)
    #expect(diffs.count == 2)
    #expect(diffs[0] == FileDiff(path: "new.txt", originalPath: "old.txt", change: .renamed))
    let hunk = DiffHunk(
      oldStart: 1, oldCount: 1, newStart: 1, newCount: 2, section: "func f() {",
      lines: [
        DiffLine(kind: .removed, text: "x", oldLine: 1, noNewlineAtEnd: true),
        DiffLine(kind: .added, text: "x", newLine: 1),
        DiffLine(kind: .added, text: "y", newLine: 2, noNewlineAtEnd: true),
      ])
    #expect(diffs[1] == FileDiff(path: "nonl.txt", hunks: [hunk]))
    #expect((diffs[1].additions, diffs[1].deletions) == (2, 1))
  }

  @Test func diffOfBinaryFilesAndPathsWithSpaces() {
    let text = """
      diff --git a/bin.dat b/bin.dat
      index bdc955b..8835708 100644
      Binary files a/bin.dat and b/bin.dat differ
      diff --git a/sp ace.txt b/sp ace.txt
      index 45b983b..65ef226 100644
      --- a/sp ace.txt\t
      +++ b/sp ace.txt\t
      @@ -1,2 +1,3 @@
       hi
      -- not a header
      +more
      +++ not a header either
       \u{20}

      """
    let diffs = GitParsers.diff(text)
    #expect(diffs.map(\.path) == ["bin.dat", "sp ace.txt"])
    #expect(diffs[0].isBinary && diffs[0].hunks.isEmpty)
    let lines = diffs[1].hunks.first?.lines ?? []
    #expect(
      lines == [
        DiffLine(kind: .context, text: "hi", oldLine: 1, newLine: 1),
        DiffLine(kind: .removed, text: "- not a header", oldLine: 2),
        DiffLine(kind: .added, text: "more", newLine: 2),
        DiffLine(kind: .added, text: "++ not a header either", newLine: 3),
        DiffLine(kind: .context, text: " ", oldLine: 3, newLine: 4),
      ])
  }

  @Test func diffOfNewAndDeletedFilesWithQuotedPaths() {
    let text = """
      diff --git "a/t\\tb.txt" "b/t\\tb.txt"
      new file mode 100644
      index 0000000..cce8b84
      --- /dev/null
      +++ "b/t\\tb.txt"
      @@ -0,0 +1 @@
      +tab
      \\ No newline at end of file
      diff --git a/é.txt b/é.txt
      deleted file mode 100644
      index c600332..0000000
      --- a/é.txt
      +++ /dev/null
      @@ -1 +0,0 @@
      -é

      """
    let diffs = GitParsers.diff(text)
    #expect(diffs.map(\.path) == ["t\tb.txt", "é.txt"])
    #expect(diffs.map(\.change) == [.added, .deleted])
    #expect(diffs[0].hunks.first?.newCount == 1)
    #expect(diffs[1].hunks.first?.lines == [DiffLine(kind: .removed, text: "é", oldLine: 1)])
  }

  @Test func unquoting() {
    #expect(GitParsers.unquote(#""t\tb""#) == "t\tb")
    #expect(GitParsers.unquote(#""\303\251.txt""#) == "é.txt")
    #expect(GitParsers.unquote(#""say \"hi\"""#) == #"say "hi""#)
    #expect(GitParsers.unquote("plain") == "plain")
    #expect(GitParsers.gitHeaderPath("a/x y b/x y") == "x y")
    #expect(GitParsers.gitHeaderPath("a/x b/z") == "z")
    #expect(GitParsers.gitHeaderPath(#""a/q\"x" "b/q\"x""#) == #"q"x"#)
  }

  @Test func hunkHeaders() {
    #expect(
      GitParsers.hunkHeader("@@ -3 +3,0 @@")
        == DiffHunk(oldStart: 3, oldCount: 1, newStart: 3, newCount: 0))
    #expect(GitParsers.hunkHeader("@@ -x +1 @@") == nil)
  }

  @Test func errorMessagesLoseGitsPrefixesAndHints() {
    let output = GitRunner.Output(
      status: 128, stdout: Data(),
      stderr: "error: Your local changes would be overwritten by checkout:\n\ta.txt\n"
        + "hint: commit first\nAborting\n")
    #expect(
      GitRunner.message(output)
        == "Your local changes would be overwritten by checkout: a.txt Aborting")
  }

  @Test func environmentIsMadeSafe() {
    let runner = GitRunner(
      executable: URL(filePath: "/usr/bin/git"),
      baseEnvironment: ["GIT_DIR": "/elsewhere/.git", "GIT_INDEX_FILE": "x", "PATH": "/bin"],
      overrides: ["GIT_CONFIG_NOSYSTEM": "1"])
    #expect(runner.environment["GIT_DIR"] == nil)
    #expect(runner.environment["GIT_INDEX_FILE"] == nil)
    #expect(runner.environment["PATH"] == "/bin")
    #expect(runner.environment["GIT_TERMINAL_PROMPT"] == "0")
    #expect(runner.environment["GIT_OPTIONAL_LOCKS"] == "0")
    #expect(runner.environment["GIT_CONFIG_NOSYSTEM"] == "1")
  }

  @Test func debounceSchedule() {
    let start = ContinuousClock.now
    func at(_ ms: Int) -> ContinuousClock.Instant { start + .milliseconds(ms) }
    var schedule = DebounceSchedule(quiet: .milliseconds(100), maxDelay: .milliseconds(250))
    #expect(schedule.deadline == nil)
    schedule.signal(at: at(0))
    schedule.signal(at: at(50))
    #expect(schedule.deadline == at(150))
    let early = schedule.fire(at: at(149))
    let due = schedule.fire(at: at(150))
    #expect(!early && due)
    #expect(schedule.deadline == nil)
    // A steady stream still fires at the max delay.
    for ms in stride(from: 1000, through: 1400, by: 50) { schedule.signal(at: at(ms)) }
    #expect(schedule.deadline == at(1250))
  }

  @Test func pathFilter() {
    let filter = GitPathFilter(root: "/r", gitDir: "/r/.git")
    for path in [
      "/r/a.txt", "/r/src/b.swift", "/r/.git/HEAD", "/r/.git/index",
      "/r/.git/refs/heads/main", "/r/.git/packed-refs", "/r/.gitignore",
    ] {
      #expect(filter.isRelevant(path), "\(path)")
    }
    for path in [
      "/r/.git/objects/ab/cdef", "/r/.git/index.lock", "/r/.git/logs/HEAD",
      "/r/.git/refs/heads/main.lock", "/elsewhere/a.txt", "/rx/a.txt",
    ] {
      #expect(!filter.isRelevant(path), "\(path)")
    }
  }
}
