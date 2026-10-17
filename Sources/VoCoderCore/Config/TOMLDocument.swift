// The one place that touches TOMLDecoder (ADR 0004: keep it swappable). The rest of the config
// layer sees a parsed document with its top-level keys, per-table keys and typed decoding of
// one top-level value at a time, so every section's errors are collected on their own.
import Foundation
import TOMLDecoder

struct TOMLDocument {
  let text: String
  private let root: TOMLTable

  /// A syntax error, with the line when TOMLDecoder names one.
  struct SyntaxError: Error {
    let line: Int?
    let message: String
  }

  init(text: String) throws(SyntaxError) {
    self.text = text
    do {
      root = try TOMLTable(source: text)
    } catch {
      throw Self.syntaxError(from: error.description)
    }
  }

  /// TOMLDecoder writes `(Line 12) Message.`; split that into its parts.
  static func syntaxError(from description: String) -> SyntaxError {
    let pattern = /^\(Line (\d+)\) (.*)$/
    if let match = description.firstMatch(of: pattern) {
      return SyntaxError(line: Int(match.1), message: String(match.2))
    }
    return SyntaxError(line: nil, message: description)
  }

  var topLevelKeys: [String] { root.keys }

  func contains(_ key: String) -> Bool { root.contains(key: key) }

  /// The keys of the table at `path` (`["keys"]`, `["keys", "bindings"]`), or nil when there is
  /// no table there.
  func keys(ofTable path: [String]) -> [String]? {
    var table = root
    for key in path {
      guard let next = try? table.table(forKey: key) else { return nil }
      table = next
    }
    return table.keys
  }

  /// The keys of each table in the array of tables at `key` (`[[repo]]`).
  func keys(ofTablesIn key: String) -> [[String]] {
    guard let array = try? root.array(forKey: key) else { return [] }
    return (0..<array.count).map { (try? array.table(atIndex: $0))?.keys ?? [] }
  }

  /// Decodes the top-level value at `key` as `type`; nil when the key is absent. Decoding
  /// errors carry the full coding path (starting with `key`).
  func decode<Value: Decodable>(_ type: Value.Type, at key: String) throws -> Value? {
    guard root.contains(key: key) else { return nil }
    return try TopLevelKey.$current.withValue(key) {
      try TOMLDecoder().decode(Envelope<Value>.self, from: text).value
    }
  }
}

/// The key `Envelope` decodes; a task-local because generic types can't hold static state.
private enum TopLevelKey {
  @TaskLocal static var current = ""
}

/// Decodes only the value under `TopLevelKey.current`, ignoring the rest of the document.
private struct Envelope<Value: Decodable>: Decodable {
  let value: Value

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    value = try container.decode(Value.self, forKey: AnyCodingKey(TopLevelKey.current))
  }
}

struct AnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init(_ string: String) {
    stringValue = string
    intValue = nil
  }
  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) {
    stringValue = "\(intValue)"
    self.intValue = intValue
  }
}
