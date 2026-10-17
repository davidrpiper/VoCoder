// Filled in by P5-01 (DESIGN §4.10). Modules depend on Core (and UI); never on each other.
import VoCoderCore

/// Registers nothing until P5-01; declares its token so `vocoder auth notion` works.
public final class NotionModule: VoCoderModule {
  public static let id: ModuleID = "notion"
  public static let secrets = [
    SecretSpec(
      name: "token", title: "Notion integration token",
      help: "https://www.notion.so/profile/integrations → new internal integration → secret")
  ]

  public init(context: ModuleContext) {}

  public func register(into registry: inout ModuleRegistry) {}
}
