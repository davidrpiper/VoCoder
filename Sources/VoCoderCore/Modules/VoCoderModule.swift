// The module system (DESIGN §4.10, ADR 0006): every feature beyond the bare shell is a module
// that declares what it contributes. Only the composition root (`vocoder`) names module types.

/// A unit of features — an integration, an agent, the demo. The composition root lists the
/// compiled-in module types; config decides which are enabled. A module is created once per
/// run, kept alive for the run, and contributes everything through `register(into:)`.
@MainActor
public protocol VoCoderModule: AnyObject {
  /// Stable id, also the config section name and Keychain service suffix (`linear`, `notion`).
  static var id: ModuleID { get }
  /// The module's config section type, if it has one (parsed from config in P1-06).
  static var configSection: (any ConfigSection.Type)? { get }

  /// Throwing marks the module as failed; the app runs without it and reports why.
  init(context: ModuleContext) throws

  /// Contributes tabs, commands, providers and sources. Called once, right after `init`.
  func register(into registry: inout ModuleRegistry)
}

extension VoCoderModule {
  public static var configSection: (any ConfigSection.Type)? { nil }
}

/// A module's typed section of the config file (`[linear]`, `[voice]`, …).
public protocol ConfigSection: Decodable, Sendable {}

/// Something that went wrong with a module: a failed init, a rejected contribution, a tab
/// factory that threw. Shown by `vocoder doctor` and logged; never fatal for the app.
public struct ModuleIssue: Sendable, Equatable, CustomStringConvertible {
  public let module: ModuleID
  public let message: String

  public init(module: ModuleID, message: String) {
    self.module = module
    self.message = message
  }

  public var description: String { "\(module): \(message)" }
}
