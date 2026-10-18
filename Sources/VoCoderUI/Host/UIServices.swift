// UI services for modules' tabs (ADR 0013): a tab that needs to move focus or edit a text
// field (the repo tab's prompt) reaches the host through the shared services. `AppShell` sets
// it before the modules load. Held weakly: the host's content holds the core, which holds the
// services.
import VoCoderCore

@MainActor
public final class UIHostReference: Sendable {
  public private(set) weak var host: UIHost?

  public init(_ host: UIHost?) { self.host = host }
}

public enum UIHostKey: ServiceKey {
  public static var defaultValue: UIHostReference? { nil }
}

extension ServiceContainer {
  /// The UI host, when a UI runs (nil in headless tests that don't set one).
  @MainActor
  public var uiHost: UIHost? {
    get { self[UIHostKey.self]?.host }
    set { self[UIHostKey.self] = UIHostReference(newValue) }
  }
}
