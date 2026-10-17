// Filled in by P4-02 (DESIGN §4.10). Modules depend on Core (and UI); never on each other.
import VoCoderCore

/// Registers nothing until P4-02.
public final class LinearModule: VoCoderModule {
  public static let id: ModuleID = "linear"

  public init(context: ModuleContext) {}

  public func register(into registry: inout ModuleRegistry) {}
}
