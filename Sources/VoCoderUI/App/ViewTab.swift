// Tabs that draw themselves (ADR 0006): Core owns the `Tab` model; modules make their tabs
// `ViewTab`s and register them here, so every tab the chrome sees has a body.
import VoCoderCore

/// A tab with content. Usually an `@Observable` class: the body re-renders when what it reads
/// changes.
@MainActor
public protocol ViewTab: Tab {
  associatedtype Content: View
  @ViewBuilder var body: Content { get }
}

extension TabFactory {
  /// A factory of drawable tabs; register it with `registry.add(tabs:)`.
  public init(
    id: TabFactoryID, placement: TabPlacement,
    makeTabs: @escaping @MainActor (TabContext) throws -> [any ViewTab]
  ) {
    self.init(id: id, placement: placement, make: { context in try makeTabs(context) })
  }
}

extension ModuleRegistry {
  public mutating func add(tabs factory: TabFactory) { add(tabFactory: factory) }
}

/// The content of `tab`, or a note if it can't draw itself.
public struct TabContent: View {
  let tab: any Tab

  public init(_ tab: any Tab) { self.tab = tab }

  public var body: some View {
    if let viewTab = tab as? any ViewTab {
      ViewGroup([viewTab.body])
    } else {
      Text("\(tab.title) has no view").foreground(.muted).centered()
    }
  }
}

extension TabBadge {
  /// How the tab bar shows the badge ("" for none).
  public var label: String {
    switch self {
    case .none: ""
    case .count(let count): count > 0 ? "\(count)" : ""
    case .working: "◐"
    case .needsYou: "●"
    case .finished: "✓"
    case .error: "✗"
    case .text(let text): text
    }
  }
}
