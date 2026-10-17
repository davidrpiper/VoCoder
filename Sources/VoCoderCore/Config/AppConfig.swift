// The config file (DESIGN §4.9, ADR 0009): `~/.config/vocoder/config.toml`. Core sections are
// typed here; each module's `[<module-id>]` section is decoded into its own `ConfigSection`.
import Foundation

/// `[ui] theme`: `auto` follows the macOS appearance.
public enum ThemePreference: String, Sendable, CaseIterable {
  case auto, dark, light
}

/// The validated config. A missing file gives the defaults.
public struct AppConfig: Sendable {
  /// The file read, or nil when there was none.
  public var file: URL?
  public var repos: [RepoRoot] = []
  public var keys = KeyBindingOverrides()
  public var theme = ThemePreference.auto
  /// `[modules] disabled`: compiled-in modules that don't load.
  public var disabledModules: Set<ModuleID> = []
  /// Parsed module sections, by module id.
  public var sections: [ModuleID: any ConfigSection] = [:]

  public init() {}

  /// The environment for creating `modules` under this config.
  @MainActor
  public func environment(
    for modules: [any VoCoderModule.Type], secrets: any SecretStore,
    services: ServiceContainer = ServiceContainer()
  ) -> ModuleEnvironment {
    let sections = sections
    return ModuleEnvironment(
      secrets: secrets, services: services, repos: repos,
      enabled: Set(modules.map { $0.id }).subtracting(disabledModules),
      configSection: { id, _ in sections[id] })
  }

  /// The enabled module types, in order.
  @MainActor
  public func enabled(_ modules: [any VoCoderModule.Type]) -> [any VoCoderModule.Type] {
    modules.filter { !disabledModules.contains($0.id) }
  }
}

/// What loading produced: the config (defaults where invalid) and every error found.
public struct ConfigLoadResult: Sendable {
  public var config: AppConfig
  public var errors: [ConfigError]
  /// False when there was no file and the defaults apply.
  public var exists: Bool
  /// The file, as shown to the user.
  public var displayPath: String

  public var isValid: Bool { errors.isEmpty }
}
