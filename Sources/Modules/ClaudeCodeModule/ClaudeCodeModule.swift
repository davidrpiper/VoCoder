// Filled in by P1-09 (DESIGN §4.10). Modules depend on Core (and UI); never on each other.
import VoCoderCore
import VoCoderUI

/// Registers nothing until P1-09.
public final class ClaudeCodeModule: VoCoderModule {
  public static let id: ModuleID = "claude-code"

  public init(context: ModuleContext) {}

  public func register(into registry: inout ModuleRegistry) {}
}
