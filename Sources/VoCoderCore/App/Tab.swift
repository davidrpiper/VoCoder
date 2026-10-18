// The tab model (DESIGN §3.2). Core owns identity, title, badge and lifecycle so app state,
// voice ("go to the api") and attention can work with tabs; how a tab draws itself is UI: tabs
// are created through `VoCoderUI`'s `ViewTab` factories (ADR 0006).

/// A tab's state indicator in the tab bar (DESIGN §3.1).
public enum TabBadge: Sendable, Equatable {
  case none
  /// Unread / attention count (integration tabs).
  case count(Int)
  /// Agent working (◐).
  case working
  /// Needs you: approval or question (●).
  case needsYou
  /// Turn finished (✓).
  case finished
  /// Error (✗).
  case error
  /// Free text (Calendar's next event).
  case text(String)
}

/// One tab. Implementations are `@Observable` classes so the chrome re-renders when the title
/// or badge changes.
@MainActor
public protocol Tab: AnyObject {
  var id: TabID { get }
  var title: String { get }
  /// Extra names for voice and the palette ("the api").
  var aliases: [String] { get }
  var badge: TabBadge { get }
  /// The repository the tab works in (repo tabs); repo commands act on it.
  var repo: RepoRoot? { get }
  /// Whether `tab.close` may close it (Home can't be closed).
  var isClosable: Bool { get }
  /// Commands the hint bar offers while this tab is shown, most useful first (those not
  /// available at the moment are skipped).
  var hintCommands: [CommandID] { get }

  /// Became the visible tab.
  func didActivate()
  /// Stopped being the visible tab.
  func didDeactivate()
  /// About to be removed (closed by the user, or the app stopping). Release resources here.
  func willClose()
}

extension Tab {
  public var aliases: [String] { [] }
  public var badge: TabBadge { .none }
  public var repo: RepoRoot? { nil }
  public var isClosable: Bool { true }
  public var hintCommands: [CommandID] { [] }
  public func didActivate() {}
  public func didDeactivate() {}
  public func willClose() {}
}

/// Where a factory's tabs go in the bar: Home, then repos, then integrations.
public enum TabPlacement: Int, Sendable, Comparable {
  case home, repo, integration

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What a tab factory may base its tabs on.
@MainActor
public struct TabContext {
  public let repos: [RepoRoot]

  public init(repos: [RepoRoot] = []) { self.repos = repos }
}

/// Creates a module's tabs at startup (one per repo root, one per integration, …). Modules
/// create factories through `VoCoderUI` (`TabFactory(id:placement:makeTabs:)` taking `ViewTab`s),
/// so every registered tab can draw itself.
@MainActor
public struct TabFactory {
  public let id: TabFactoryID
  public let placement: TabPlacement
  package let make: @MainActor (TabContext) throws -> [any Tab]

  package init(
    id: TabFactoryID, placement: TabPlacement,
    make: @escaping @MainActor (TabContext) throws -> [any Tab]
  ) {
    self.id = id
    self.placement = placement
    self.make = make
  }

  public func makeTabs(in context: TabContext) throws -> [any Tab] { try make(context) }
}
