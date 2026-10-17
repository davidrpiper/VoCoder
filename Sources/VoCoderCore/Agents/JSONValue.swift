import Foundation

/// Any JSON value. Agent tool inputs are free-form JSON whose shape depends on the tool, so
/// they travel as this instead of vendor types.
public enum JSONValue: Sendable, Hashable, Codable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// Parses one JSON document.
  public init(parsing text: some StringProtocol) throws {
    self = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  }

  /// Compact JSON with sorted keys (stable for tests and logs).
  public var jsonString: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
  }

  public subscript(key: String) -> JSONValue? {
    if case .object(let object) = self { object[key] } else { nil }
  }

  public var string: String? { if case .string(let value) = self { value } else { nil } }
  public var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
  public var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
  public var object: [String: JSONValue]? {
    if case .object(let value) = self { value } else { nil }
  }

  public var int: Int? {
    switch self {
    case .int(let value): value
    case .double(let value): Int(exactly: value)
    default: nil
    }
  }

  public var double: Double? {
    switch self {
    case .int(let value): Double(value)
    case .double(let value): value
    default: nil
    }
  }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
  ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral,
  ExpressibleByNilLiteral
{
  public init(stringLiteral value: String) { self = .string(value) }
  public init(integerLiteral value: Int) { self = .int(value) }
  public init(booleanLiteral value: Bool) { self = .bool(value) }
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
  }
  public init(nilLiteral: ()) { self = .null }
}
