import Foundation

/// One input a command needs ("which tab", "comment text"). The palette prompts for missing
/// parameters in order; voice fills them from slots; key bindings may fix them.
public struct CommandParameter: Sendable {
  public enum Kind: Sendable {
    case text
    /// A whole number, optionally limited to `range`.
    case integer(ClosedRange<Int>?)
    /// One of the choices offered in the current context (tabs, statuses, …).
    case choice(@MainActor @Sendable (CommandContext) -> [Choice])
  }

  public struct Choice: Sendable, Equatable {
    /// What the command receives (as `.text`).
    public let value: String
    /// What the palette shows.
    public let title: String

    public init(value: String, title: String) {
      self.value = value
      self.title = title
    }
  }

  public let name: String
  /// The prompt ("Tab", "Comment").
  public let title: String
  public let kind: Kind
  /// Optional parameters are not prompted for.
  public let isOptional: Bool

  public init(_ name: String, title: String, kind: Kind = .text, isOptional: Bool = false) {
    self.name = name
    self.title = title
    self.kind = kind
    self.isOptional = isOptional
  }

  /// `value` converted for this parameter, nil when it doesn't fit.
  @MainActor
  public func validate(_ value: CommandValue, in context: CommandContext) -> CommandValue? {
    switch kind {
    case .text:
      return .text(value.text)
    case .integer(let range):
      guard let number = value.integer, range?.contains(number) ?? true else { return nil }
      return .integer(number)
    case .choice(let choices):
      return choices(context).contains { $0.value == value.text } ? .text(value.text) : nil
    }
  }
}

/// A parameter value.
public enum CommandValue: Sendable, Hashable, CustomStringConvertible,
  ExpressibleByStringLiteral, ExpressibleByIntegerLiteral
{
  case text(String)
  case integer(Int)

  public init(stringLiteral value: String) { self = .text(value) }
  public init(integerLiteral value: Int) { self = .integer(value) }

  public var text: String {
    switch self {
    case .text(let text): text
    case .integer(let number): String(number)
    }
  }

  public var integer: Int? {
    switch self {
    case .text(let text): Int(text.trimmingCharacters(in: .whitespaces))
    case .integer(let number): number
    }
  }

  public var description: String { text }
}

/// Parameter values by name.
public struct CommandArguments: Sendable, Hashable, ExpressibleByDictionaryLiteral {
  public var values: [String: CommandValue]

  public init(_ values: [String: CommandValue] = [:]) { self.values = values }

  public init(dictionaryLiteral elements: (String, CommandValue)...) {
    self.values = Dictionary(elements) { _, last in last }
  }

  public subscript(name: String) -> CommandValue? {
    get { values[name] }
    set { values[name] = newValue }
  }

  public func text(_ name: String) -> String? { values[name]?.text }
  public func integer(_ name: String) -> Int? { values[name]?.integer }

  public var isEmpty: Bool { values.isEmpty }
}
