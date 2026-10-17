import Foundation

/// Minimal dynamic JSON value. Sendable, so events can cross actor boundaries.
enum JSON: Sendable, Hashable, Codable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSON])
  case object([String: JSON])

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(Int.self) {
      self = .int(v)
    } else if let v = try? c.decode(Double.self) {
      self = .double(v)
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode([JSON].self) {
      self = .array(v)
    } else {
      self = .object(try c.decode([String: JSON].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .int(let v): try c.encode(v)
    case .double(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }

  static func parse(_ line: String) throws -> JSON {
    try JSONDecoder().decode(JSON.self, from: Data(line.utf8))
  }

  var line: String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return String(decoding: try! enc.encode(self), as: UTF8.self)
  }

  subscript(key: String) -> JSON? {
    if case .object(let o) = self { return o[key] }
    return nil
  }

  var string: String? { if case .string(let s) = self { return s } else { return nil } }
  var int: Int? { if case .int(let i) = self { return i } else { return nil } }
  var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
  var array: [JSON]? { if case .array(let a) = self { return a } else { return nil } }
  var object: [String: JSON]? { if case .object(let o) = self { return o } else { return nil } }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral,
  ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral
{
  init(stringLiteral value: String) { self = .string(value) }
  init(dictionaryLiteral elements: (String, JSON)...) {
    self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
  }
  init(arrayLiteral elements: JSON...) { self = .array(elements) }
  init(booleanLiteral value: Bool) { self = .bool(value) }
  init(integerLiteral value: Int) { self = .int(value) }
}
