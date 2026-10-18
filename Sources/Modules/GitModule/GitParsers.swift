import Foundation
import VoCoderCore

/// Parsers for git's machine-readable output. Pure, so they're tested on literal strings.
public enum GitParsers {
  // MARK: Status

  /// `git status --porcelain=v2 -z --branch --untracked-files=all`.
  public static func status(_ data: Data) -> RepoStatus {
    var status = RepoStatus()
    let fields = data.split(separator: 0, omittingEmptySubsequences: false)
      .map { String(decoding: $0, as: UTF8.self) }
    var index = 0
    while index < fields.count {
      let field = fields[index]
      index += 1
      guard let kind = field.first else { continue }
      switch kind {
      case "#":
        header(field, into: &status)
      case "1":
        // 1 XY sub mH mI mW hH hI path
        let parts = field.split(separator: " ", maxSplits: 8).map(String.init)
        guard parts.count == 9 else { continue }
        status.files.append(tracked(xy: parts[1], path: parts[8]))
      case "2":
        // 2 XY sub mH mI mW hH hI Xscore path NUL origPath
        let parts = field.split(separator: " ", maxSplits: 9).map(String.init)
        guard parts.count == 10, index < fields.count else { continue }
        var file = tracked(xy: parts[1], path: parts[9])
        file.originalPath = fields[index]
        index += 1
        status.files.append(file)
      case "u":
        // u XY sub m1 m2 m3 mW h1 h2 h3 path
        let parts = field.split(separator: " ", maxSplits: 10).map(String.init)
        guard parts.count == 11 else { continue }
        status.files.append(ChangedFile(path: parts[10], isConflicted: true))
      case "?":
        status.files.append(ChangedFile(path: String(field.dropFirst(2)), isUntracked: true))
      default:
        continue  // "!" (ignored) isn't requested
      }
    }
    status.files.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
    return status
  }

  private static func header(_ field: String, into status: inout RepoStatus) {
    let parts = field.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count == 3 else { return }
    let value = parts[2]
    switch parts[1] {
    case "branch.oid": status.head = value == "(initial)" ? nil : CommitID(value)
    case "branch.head": status.branch = value == "(detached)" ? nil : value
    case "branch.upstream": status.upstream = value
    case "branch.ab":
      let counts = value.split(separator: " ").map { Int($0.dropFirst()) ?? 0 }
      if counts.count == 2 { (status.ahead, status.behind) = (counts[0], counts[1]) }
    default: break
    }
  }

  private static func tracked(xy: String, path: String) -> ChangedFile {
    let codes = Array(xy)
    return ChangedFile(
      path: path, staged: codes.first.flatMap(change),
      unstaged: codes.dropFirst().first.flatMap(change))
  }

  static func change(_ code: Character) -> ChangedFile.Change? {
    switch code {
    case "M": .modified
    case "A": .added
    case "D": .deleted
    case "R": .renamed
    case "C": .copied
    case "T": .typeChanged
    default: nil
    }
  }

  // MARK: Branches

  /// The `for-each-ref` format `branches(_:)` reads.
  public static let branchFormat = "%(refname:short)%00%(objectname)%00%(upstream:short)%00%(HEAD)"

  /// `git for-each-ref --format=<branchFormat> refs/heads`.
  public static func branches(_ text: String) -> [Branch] {
    text.split(separator: "\n").compactMap { line in
      let parts = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
      guard parts.count == 4, !parts[0].isEmpty else { return nil }
      return Branch(
        name: parts[0], head: CommitID(parts[1]), upstream: parts[2].isEmpty ? nil : parts[2],
        isCurrent: parts[3] == "*")
    }
    .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
  }

  // MARK: Diff

  /// `git diff --no-color --no-ext-diff -M` (also `--no-index` for untracked files).
  public static func diff(_ text: String) -> [FileDiff] {
    var diffs: [FileDiff] = []
    var current: FileDiff?
    var hunk: DiffHunk?
    var oldLine = 0
    var newLine = 0

    func finishHunk() {
      if let done = hunk { current?.hunks.append(done) }
      hunk = nil
    }
    func finishFile() {
      finishHunk()
      if let done = current { diffs.append(done) }
      current = nil
    }

    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(raw)
      if line.hasPrefix("diff --git ") {
        finishFile()
        let path = gitHeaderPath(String(line.dropFirst("diff --git ".count))) ?? ""
        current = FileDiff(path: path)
        continue
      }
      guard current != nil else { continue }
      if hunk != nil {
        if let marker = line.first, "+- \\".contains(marker) {
          let body = String(line.dropFirst())
          switch marker {
          case "+":
            hunk?.lines.append(DiffLine(kind: .added, text: body, newLine: newLine))
            newLine += 1
          case "-":
            hunk?.lines.append(DiffLine(kind: .removed, text: body, oldLine: oldLine))
            oldLine += 1
          case " ":
            hunk?.lines.append(
              DiffLine(kind: .context, text: body, oldLine: oldLine, newLine: newLine))
            oldLine += 1
            newLine += 1
          default:  // "\ No newline at end of file"
            if let last = hunk?.lines.indices.last { hunk?.lines[last].noNewlineAtEnd = true }
          }
          continue
        }
        if line.isEmpty { continue }  // the final line break
        finishHunk()
      }
      if line.hasPrefix("@@ "), let parsed = hunkHeader(line) {
        hunk = parsed
        oldLine = parsed.oldStart
        newLine = parsed.newStart
      } else if line.hasPrefix("new file mode") {
        current?.change = .added
      } else if line.hasPrefix("deleted file mode") {
        current?.change = .deleted
      } else if line.hasPrefix("rename from ") {
        current?.change = .renamed
        current?.originalPath = unquote(String(line.dropFirst("rename from ".count)))
      } else if line.hasPrefix("rename to ") {
        current?.path = unquote(String(line.dropFirst("rename to ".count)))
      } else if line.hasPrefix("copy from ") {
        current?.change = .copied
        current?.originalPath = unquote(String(line.dropFirst("copy from ".count)))
      } else if line.hasPrefix("copy to ") {
        current?.path = unquote(String(line.dropFirst("copy to ".count)))
      } else if line.hasPrefix("old mode") || line.hasPrefix("new mode") {
        continue
      } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
        current?.isBinary = true
      } else if line.hasPrefix("+++ "), let path = sidePath(line.dropFirst(4)) {
        current?.path = path
      }  // "--- a/path", "index …", "similarity index …": nothing new
    }
    finishFile()
    return diffs
  }

  /// `@@ -1,3 +1,4 @@ section`.
  static func hunkHeader(_ line: String) -> DiffHunk? {
    let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false)
    guard parts.count >= 4, parts[0] == "@@", parts[3] == "@@",
      let old = range(parts[1], marker: "-"), let new = range(parts[2], marker: "+")
    else { return nil }
    let section = parts.count == 5 ? String(parts[4]) : ""
    return DiffHunk(
      oldStart: old.start, oldCount: old.count, newStart: new.start, newCount: new.count,
      section: section)
  }

  private static func range(_ text: Substring, marker: Character) -> (start: Int, count: Int)? {
    guard text.first == marker else { return nil }
    let numbers = text.dropFirst().split(separator: ",").map { Int($0) }
    guard let start = numbers.first ?? nil else { return nil }
    let count = numbers.count > 1 ? numbers[1] : 1
    guard let count else { return nil }
    return (start, count)
  }

  /// `a/path b/path` from a `diff --git` line. Unquoted paths may contain spaces, so a
  /// same-path header is split in the middle; renames are corrected by `rename to` later.
  static func gitHeaderPath(_ rest: String) -> String? {
    if rest.hasPrefix("\"") {
      let tokens = quotedTokens(rest)
      return tokens.last.map { stripSide($0) }
    }
    let characters = Array(rest)
    if characters.count % 2 == 1 {
      let half = (characters.count - 1) / 2
      let first = String(characters[..<half])
      let second = String(characters[(half + 1)...])
      if characters[half] == " ", first.dropFirst(2) == second.dropFirst(2) {
        return stripSide(second)
      }
    }
    if let range = rest.range(of: " b/", options: .backwards) {
      return String(rest[range.upperBound...])
    }
    return nil
  }

  /// The path of a `---`/`+++` line, nil for `/dev/null`.
  private static func sidePath(_ text: Substring) -> String? {
    var path = String(text)
    if let tab = path.firstIndex(of: "\t") { path = String(path[..<tab]) }
    path = unquote(path)
    guard path != "/dev/null" else { return nil }
    return stripSide(path)
  }

  private static func stripSide(_ path: String) -> String {
    path.hasPrefix("a/") || path.hasPrefix("b/") ? String(path.dropFirst(2)) : path
  }

  /// Splits `"a/x" "b/y"` (or a mix of quoted and plain) into its two paths, unquoted.
  private static func quotedTokens(_ text: String) -> [String] {
    var tokens: [String] = []
    var rest = Substring(text)
    while !rest.isEmpty {
      rest = rest.drop { $0 == " " }
      if rest.first == "\"" {
        var end = rest.index(after: rest.startIndex)
        var escaped = false
        while end < rest.endIndex {
          let character = rest[end]
          if escaped {
            escaped = false
          } else if character == "\\" {
            escaped = true
          } else if character == "\"" {
            break
          }
          end = rest.index(after: end)
        }
        let token = rest[rest.startIndex...min(end, rest.index(before: rest.endIndex))]
        tokens.append(unquote(String(token)))
        rest = end < rest.endIndex ? rest[rest.index(after: end)...] : ""
      } else {
        let end = rest.firstIndex(of: " ") ?? rest.endIndex
        tokens.append(String(rest[..<end]))
        rest = rest[end...]
      }
    }
    return tokens
  }

  /// Undoes git's C-style quoting (`"tab\there"`, octal UTF-8 bytes `"\303\251"`).
  public static func unquote(_ text: String) -> String {
    guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
    var bytes: [UInt8] = []
    var characters = Array(text.utf8.dropFirst().dropLast())[...]
    while let byte = characters.popFirst() {
      guard byte == UInt8(ascii: "\\"), let next = characters.popFirst() else {
        bytes.append(byte)
        continue
      }
      switch next {
      case UInt8(ascii: "n"): bytes.append(0x0A)
      case UInt8(ascii: "t"): bytes.append(0x09)
      case UInt8(ascii: "r"): bytes.append(0x0D)
      case UInt8(ascii: "a"): bytes.append(0x07)
      case UInt8(ascii: "b"): bytes.append(0x08)
      case UInt8(ascii: "f"): bytes.append(0x0C)
      case UInt8(ascii: "v"): bytes.append(0x0B)
      case UInt8(ascii: "0")...UInt8(ascii: "7"):
        var value = Int(next - UInt8(ascii: "0"))
        for _ in 0..<2 {
          guard let digit = characters.first,
            (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(digit)
          else { break }
          characters.removeFirst()
          value = value * 8 + Int(digit - UInt8(ascii: "0"))
        }
        bytes.append(UInt8(truncatingIfNeeded: value))
      default: bytes.append(next)
      }
    }
    return String(decoding: bytes, as: UTF8.self)
  }
}
