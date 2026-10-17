// The module system (DESIGN §4.10, ADR 0006): every feature beyond the bare shell is a module
// that declares what it contributes. Only the composition root (`vocoder`) names module types.

/// A unit of features — an integration, an agent, the demo. The composition root lists the
/// compiled-in module types; config decides which are enabled. A module is created once per
/// run, kept alive for the run, and contributes everything through `register(into:)`.
@MainActor
public protocol VoCoderModule: AnyObject {
  /// Stable id, also the config section name and Keychain service suffix (`linear`, `notion`).
  static var id: ModuleID { get }
  /// The module's config section type (`[<id>]` in the config file), if it has one.
  static var configSection: (any ConfigSection.Type)? { get }
  /// The secrets the module reads from the `SecretStore`; `vocoder auth <id>` asks for them and
  /// `vocoder doctor` checks that they're set.
  static var secrets: [SecretSpec] { get }

  /// Throwing marks the module as failed; the app runs without it and reports why.
  init(context: ModuleContext) throws

  /// Contributes tabs, commands, providers and sources. Called once, right after `init`.
  func register(into registry: inout ModuleRegistry)
}

extension VoCoderModule {
  public static var configSection: (any ConfigSection.Type)? { nil }
  public static var secrets: [SecretSpec] { [] }
}

/// A module's typed section of the config file (`[linear]`, `[claude-code]`, …). Decoding
/// errors become config errors that stop startup (ADR 0009); throw `DecodingError`s with a
/// readable `debugDescription` for invalid values.
public protocol ConfigSection: Decodable, Sendable {
  /// The keys the section accepts; others are reported as unknown (typos). Nil skips the check.
  static var keys: [String]? { get }
}

extension ConfigSection {
  public static var keys: [String]? { nil }
}

/// A secret a module needs, as `vocoder auth` asks for it.
public struct SecretSpec: Sendable, Equatable {
  /// The Keychain account within the module (`api-key`).
  public let name: String
  /// What to ask for (`Linear API key`).
  public let title: String
  /// Where to get it.
  public let help: String

  public init(name: String, title: String, help: String) {
    self.name = name
    self.title = title
    self.help = help
  }
}

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
