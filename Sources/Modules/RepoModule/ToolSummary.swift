// One-line summaries and truncation for tool calls in the conversation. Vendor-neutral: it reads
// common input keys instead of knowing a backend's tool names.
import Foundation
import VoCoderCore

enum ToolSummary {
  /// Input keys that say what a call is about, most telling first.
  static let keys = [
    "command", "file_path", "path", "pattern", "url", "query", "description", "subject",
    "prompt",
  ]

  /// "git status", "Sources/App.swift", or the first string in the input; "" when none. Paths
  /// under one of `roots` (the repo, as written and resolved) are shown relative to it.
  static func summary(name: String, input: JSONValue, roots: [String] = []) -> String {
    for key in keys {
      if let text = input[key]?.string, !text.isEmpty {
        return oneLine(relative(text, to: roots))
      }
    }
    if let first = input.object?.sorted(by: { $0.key < $1.key }).lazy
      .compactMap({ $0.value.string }).first
    {
      return oneLine(first)
    }
    return ""
  }

  static func relative(_ path: String, to roots: [String]) -> String {
    for root in roots where path.hasPrefix(root + "/") {
      return String(path.dropFirst(root.count + 1))
    }
    return path
  }

  /// A directory's path as written and with symlinks resolved (`/var` is `/private/var`): tools
  /// may report either.
  static func roots(of url: URL) -> [String] {
    let path = url.standardizedFileURL.path
    guard let resolved = realpath(path, nil) else { return [path] }
    defer { free(resolved) }
    let real = String(cString: resolved)
    return real == path ? [path] : [path, real]
  }

  /// The first line, with a "…" when anything was dropped, at most `limit` characters.
  static func oneLine(_ text: String, limit: Int = 200) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let first = trimmed.prefix { $0 != "\n" && $0 != "\r\n" }
    var line = String(first.prefix(limit))
    if line.count < trimmed.count { line += " …" }
    return line
  }

  /// At most `maxLines` lines of `text`, and a note of how many were left out.
  static func truncated(_ text: String, maxLines: Int) -> (lines: [String], omitted: Int) {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if lines.last?.isEmpty == true { lines.removeLast() }
    return (Array(lines.prefix(maxLines)), max(0, lines.count - maxLines))
  }

  /// The input as shown when a call is expanded or needs approval: the summary key's full text
  /// (a whole shell command), otherwise compact JSON.
  static func detail(of input: JSONValue) -> String {
    for key in keys {
      if let text = input[key]?.string, !text.isEmpty { return text }
    }
    return input.jsonString
  }
}
