// Filled in by P1-08 (DESIGN §4.10). Modules depend on Core (and UI); never on each other.
import VoCoderCore

/// Registers nothing until P1-08.
public final class GitModule: VoCoderModule {
  public static let id: ModuleID = "git"

  public init(context: ModuleContext) {}

  public func register(into registry: inout ModuleRegistry) {}
}
