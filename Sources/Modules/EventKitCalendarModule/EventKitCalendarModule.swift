// Filled in by P3-03 (DESIGN §4.10). Modules depend on Core (and UI); never on each other.
import VoCoderCore

/// Registers nothing until P3-03.
public final class EventKitCalendarModule: VoCoderModule {
  public static let id: ModuleID = "calendar"

  public init(context: ModuleContext) {}

  public func register(into registry: inout ModuleRegistry) {}
}
