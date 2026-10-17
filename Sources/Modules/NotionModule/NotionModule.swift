// Filled in by P5-01 (DESIGN §4.10). Modules depend on Core (and UI); never on each other.
import VoCoderCore

/// Registers nothing until P5-01.
public final class NotionModule: VoCoderModule {
  public static let id: ModuleID = "notion"

  public init(context: ModuleContext) {}

  public func register(into registry: inout ModuleRegistry) {}
}
