/// A stable string identity, typed by what it identifies so a `TabID` can't be passed where a
/// `CommandID` is expected. Ids are lower-case and dotted by convention (`claude-code`,
/// `agent.approve`).
public struct Identifier<Kind>: RawRepresentable, Hashable, Comparable, Sendable,
  CustomStringConvertible, ExpressibleByStringLiteral
{
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }

  public var description: String { rawValue }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Phantom kinds for `Identifier`.
public enum IdentifierKind {
  public enum Module {}
  public enum Provider {}
  public enum Tab {}
  public enum TabFactory {}
  public enum Command {}
  public enum Workflow {}
  public enum AttentionItem {}
}

public typealias ModuleID = Identifier<IdentifierKind.Module>
/// Identifies a contributed service: agent backend, tracker, model, attention source, ….
public typealias ProviderID = Identifier<IdentifierKind.Provider>
public typealias TabID = Identifier<IdentifierKind.Tab>
public typealias TabFactoryID = Identifier<IdentifierKind.TabFactory>
public typealias CommandID = Identifier<IdentifierKind.Command>
public typealias WorkflowID = Identifier<IdentifierKind.Workflow>
public typealias AttentionItemID = Identifier<IdentifierKind.AttentionItem>
