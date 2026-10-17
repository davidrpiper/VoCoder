import Foundation

/// A problem in the config file, phrased so it can be fixed without reading code: where
/// (file, line, key path), what's wrong and, where it helps, what to write instead.
public struct ConfigError: Error, Sendable, Equatable, CustomStringConvertible {
  /// The file as shown to the user (`~/.config/vocoder/config.toml`).
  public var file: String
  public var line: Int?
  /// The key path (`keys.bindings."tab.next"`, `repo[2].path`); nil for the whole file.
  public var keyPath: String?
  public var message: String
  public var hint: String?

  public init(
    file: String, line: Int? = nil, keyPath: String? = nil, message: String, hint: String? = nil
  ) {
    self.file = file
    self.line = line
    self.keyPath = keyPath
    self.message = message
    self.hint = hint
  }

  /// `config.toml:12: keys.leader: 'ctl+space' is not a key` and an indented hint line.
  public var description: String {
    var text = file
    if let line { text += ":\(line)" }
    text += ": "
    if let keyPath { text += "\(keyPath): " }
    text += message
    if let hint { text += "\n    \(hint)" }
    return text
  }
}

/// A key path within the document: table and key names and (1-based) array positions.
struct ConfigPath: Equatable {
  enum Component: Equatable {
    case key(String)
    case index(Int)
  }

  var components: [Component]

  init(_ components: [Component]) { self.components = components }

  init(_ keys: String...) { components = keys.map(Component.key) }

  init(codingPath: [any CodingKey]) {
    components = codingPath.map { key in
      key.intValue.map { .index($0 + 1) } ?? .key(key.stringValue)
    }
  }

  func appending(_ component: Component) -> ConfigPath {
    ConfigPath(components + [component])
  }

  /// `keys.bindings."tab.next"`, `repo[2].path`.
  var description: String {
    var text = ""
    for component in components {
      switch component {
      case .index(let index):
        text += "[\(index)]"
      case .key(let key):
        if !text.isEmpty { text += "." }
        text += Self.isBare(key) ? key : "\"\(key)\""
      }
    }
    return text
  }

  static func isBare(_ key: String) -> Bool {
    !key.isEmpty
      && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
  }
}

/// Finds the line a key path is written on, for error messages. A heuristic over the text:
/// it understands `[table]`, `[[array]]` and `key = …` lines, which is how the template and
/// DESIGN §4.9 write config; inline tables fall back to their table's line.
struct ConfigLineLocator {
  private let lines: [Substring]

  init(text: String) {
    lines = text.split(separator: "\n", omittingEmptySubsequences: false)
  }

  func line(of path: ConfigPath) -> Int? {
    // Split the path into the table header part and the key inside it: try the longest table
    // prefix that has a header line.
    let components = path.components
    for split in stride(from: components.count, through: 1, by: -1) {
      let table = Array(components[..<split])
      guard let header = headerLine(for: table) else { continue }
      guard split < components.count, case .key(let key) = components[split] else {
        return header + 1
      }
      return keyLine(key, after: header).map { $0 + 1 } ?? header + 1
    }
    // A top-level key (before any table).
    if case .key(let key)? = components.first {
      return keyLine(key, after: -1).map { $0 + 1 }
    }
    return nil
  }

  /// The index of the header line of `table` (`[keys.bindings]`, the n-th `[[repo]]`).
  private func headerLine(for table: [ConfigPath.Component]) -> Int? {
    var names: [String] = []
    var arrayIndex: Int?
    for component in table {
      switch component {
      case .key(let key): names.append(key)
      case .index(let index):
        // Only `[[name]]` arrays of tables (an index right after the last name) are supported.
        guard arrayIndex == nil, component == table.last else { return nil }
        arrayIndex = index
      }
    }
    let joined = names.map { ConfigPath.isBare($0) ? $0 : "\"\($0)\"" }.joined(separator: ".")
    var seen = 0
    for (number, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if let arrayIndex {
        guard trimmed.hasPrefix("[["), let name = Self.headerName(trimmed, brackets: 2),
          name == joined
        else { continue }
        seen += 1
        if seen == arrayIndex { return number }
      } else if !trimmed.hasPrefix("[["), trimmed.hasPrefix("["),
        Self.headerName(trimmed, brackets: 1) == joined
      {
        return number
      }
    }
    return nil
  }

  private static func headerName(_ line: String, brackets: Int) -> String? {
    let open = String(repeating: "[", count: brackets)
    let close = String(repeating: "]", count: brackets)
    guard line.hasPrefix(open), let end = line.range(of: close) else { return nil }
    let inner = line[line.index(line.startIndex, offsetBy: brackets)..<end.lowerBound]
    return inner.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }
      .joined(separator: ".")
  }

  /// The index of the line assigning `key` after line `header`, before the next table header.
  private func keyLine(_ key: String, after header: Int) -> Int? {
    let spellings = [key, "\"\(key)\"", "'\(key)'"]
    for number in (header + 1)..<lines.count {
      let trimmed = lines[number].trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("[") { return nil }
      for spelling in spellings where trimmed.hasPrefix(spelling) {
        let rest = trimmed.dropFirst(spelling.count).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("=") { return number }
      }
    }
    return nil
  }
}

/// Spelling suggestions for unknown names.
enum Suggestion {
  /// The closest candidate within two edits, if any.
  static func closest(to word: String, in candidates: [String]) -> String? {
    candidates
      .map { (candidate: $0, distance: distance(word.lowercased(), $0.lowercased())) }
      .filter { $0.distance <= 2 && $0.distance < word.count }
      .min { $0.distance < $1.distance }?.candidate
  }

  static func distance(_ a: String, _ b: String) -> Int {
    let a = Array(a)
    let b = Array(b)
    if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
    var previous = Array(0...b.count)
    for i in 1...a.count {
      var current = [i] + Array(repeating: 0, count: b.count)
      for j in 1...b.count {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
      }
      previous = current
    }
    return previous[b.count]
  }
}
