import Foundation

/// What a module gets at creation: its config section, secrets, a logger and shared services.
@MainActor
public struct ModuleContext {
  public let module: ModuleID
  public let log: Log
  public let secrets: any SecretStore
  public let services: ServiceContainer
  /// Configured repo roots (one repo tab each).
  public let repos: [RepoRoot]
  private let section: (any ConfigSection)?

  public init(
    module: ModuleID, secrets: any SecretStore, services: ServiceContainer = ServiceContainer(),
    repos: [RepoRoot] = [], section: (any ConfigSection)? = nil
  ) {
    self.module = module
    self.log = Log(category: "module.\(module)")
    self.secrets = secrets
    self.services = services
    self.repos = repos
    self.section = section
  }

  /// The module's parsed config section, or nil when the config has none.
  public func config<Section: ConfigSection>(_ type: Section.Type = Section.self) -> Section? {
    section as? Section
  }
}

/// A repository root from the config; each gets a repo tab.
public struct RepoRoot: Sendable, Equatable {
  public let url: URL
  /// Spoken and typed names ("the api", "api server").
  public let aliases: [String]

  public init(url: URL, aliases: [String] = []) {
    self.url = url
    self.aliases = aliases
  }

  /// The directory name, used as the default tab title.
  public var name: String { url.lastPathComponent }
}

/// Where secrets live (the Keychain from P1-06). Never log values read from it.
public protocol SecretStore: Sendable {
  func secret(for key: SecretKey) throws -> String?
  func setSecret(_ value: String, for key: SecretKey) throws
  func removeSecret(for key: SecretKey) throws
}

/// A secret's address: the owning module and a name within it (`linear` / `api-key`).
public struct SecretKey: Hashable, Sendable, CustomStringConvertible {
  public let module: ModuleID
  public let name: String

  public init(module: ModuleID, name: String) {
    self.module = module
    self.name = name
  }

  public var description: String { "\(module)/\(name)" }
}

/// A shared service's type and default value; extend `ServiceContainer` with a property for it.
public protocol ServiceKey {
  associatedtype Value: Sendable
  static var defaultValue: Value { get }
}

/// Shared infrastructure handed to every module (clock, later process runner, HTTP). Built by
/// the composition root; read-only for modules. Features modules offer each other go through
/// registries instead.
public struct ServiceContainer: Sendable {
  private var values: [ObjectIdentifier: any Sendable] = [:]

  public init() {}

  public subscript<Key: ServiceKey>(key: Key.Type) -> Key.Value {
    get { values[ObjectIdentifier(key)] as? Key.Value ?? Key.defaultValue }
    set { values[ObjectIdentifier(key)] = newValue }
  }
}

public enum NowServiceKey: ServiceKey {
  public static var defaultValue: @Sendable () -> Date { { Date() } }
}

extension ServiceContainer {
  /// The current time; replaced by tests.
  public var now: @Sendable () -> Date {
    get { self[NowServiceKey.self] }
    set { self[NowServiceKey.self] = newValue }
  }
}
