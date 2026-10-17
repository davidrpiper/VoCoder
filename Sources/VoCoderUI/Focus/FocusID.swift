/// Stable identity of a focusable view or focus scope. Must be unique within a render; derive
/// children from their parent (`list.appending("row-3")`) to keep them so.
public struct FocusID: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
  public let rawValue: String

  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }

  public func appending(_ component: String) -> FocusID { FocusID(rawValue + "/" + component) }

  public var description: String { rawValue }
}
