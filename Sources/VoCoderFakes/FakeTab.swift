import Observation
import VoCoderCore

/// A tab with settable title and badge that records its lifecycle calls. Core-level only (it
/// doesn't draw): UI tests and the demo use `ViewTab`s.
@MainActor
@Observable
public final class FakeTab: Tab {
  public let id: TabID
  public var title: String
  public var aliases: [String]
  public var badge: TabBadge
  /// "activate", "deactivate", "close", in call order.
  public private(set) var lifecycle: [String] = []

  public init(
    id: TabID, title: String? = nil, aliases: [String] = [], badge: TabBadge = .none
  ) {
    self.id = id
    self.title = title ?? id.rawValue
    self.aliases = aliases
    self.badge = badge
  }

  public func didActivate() { lifecycle.append("activate") }
  public func didDeactivate() { lifecycle.append("deactivate") }
  public func willClose() { lifecycle.append("close") }
}

extension TabFactory {
  /// A factory of `FakeTab`s (Core tests; modules use `VoCoderUI`'s `ViewTab` factories).
  public static func fake(
    id: TabFactoryID, placement: TabPlacement = .integration,
    make: @escaping @MainActor (TabContext) throws -> [FakeTab]
  ) -> TabFactory {
    TabFactory(id: id, placement: placement, make: { try make($0) })
  }
}

extension ModuleRegistry {
  /// Registers a `FakeTab` factory (Core tests).
  public mutating func add(fakeTabs factory: TabFactory) { add(tabFactory: factory) }
}
