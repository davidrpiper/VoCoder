/// Parses a module's config section (nil when the file has none). Errors fail the module.
public typealias ConfigSectionReader =
  @MainActor (_ module: ModuleID, _ type: any ConfigSection.Type) throws -> (any ConfigSection)?

/// What the composition root provides for creating modules.
@MainActor
public struct ModuleEnvironment {
  public var secrets: any SecretStore
  public var services: ServiceContainer
  public var repos: [RepoRoot]
  /// Module ids to load; nil loads every compiled-in module (config decides from P1-06).
  public var enabled: Set<ModuleID>?
  public var configSection: ConfigSectionReader

  public init(
    secrets: any SecretStore, services: ServiceContainer = ServiceContainer(),
    repos: [RepoRoot] = [], enabled: Set<ModuleID>? = nil,
    configSection: @escaping ConfigSectionReader = { _, _ in nil }
  ) {
    self.secrets = secrets
    self.services = services
    self.repos = repos
    self.enabled = enabled
    self.configSection = configSection
  }
}

/// The result of loading modules: the live modules and everything they contributed.
@MainActor
public struct LoadedModules {
  public let modules: [any VoCoderModule]
  public let registry: ModuleRegistry
  /// Failed inits, bad config sections, duplicate ids and rejected contributions.
  public let issues: [ModuleIssue]

  public var moduleIDs: [ModuleID] { modules.map { type(of: $0).id } }
}

/// Creates and registers the enabled modules in list order. One module failing never stops
/// the others.
@MainActor
public enum ModuleLoader {
  private static let log = Log(category: "modules")

  public static func load(
    _ types: [any VoCoderModule.Type], environment: ModuleEnvironment
  ) -> LoadedModules {
    var modules: [any VoCoderModule] = []
    var registry = ModuleRegistry()
    var issues: [ModuleIssue] = []
    var seen: Set<ModuleID> = []

    for type in types {
      let id = type.id
      guard environment.enabled?.contains(id) ?? true else {
        log.info("module \(id) disabled")
        continue
      }
      guard seen.insert(id).inserted else {
        issues.append(ModuleIssue(module: id, message: "duplicate module id; \(type) not loaded"))
        continue
      }
      do {
        let section = try type.configSection.flatMap { try environment.configSection(id, $0) }
        let context = ModuleContext(
          module: id, secrets: environment.secrets, services: environment.services,
          repos: environment.repos, section: section)
        let module = try type.init(context: context)
        registry.currentModule = id
        module.register(into: &registry)
        modules.append(module)
        log.info("module \(id) loaded")
      } catch {
        issues.append(ModuleIssue(module: id, message: "failed to start: \(error)"))
      }
    }
    issues += registry.issues
    for issue in issues { log.error("module issue: \(issue)") }
    return LoadedModules(modules: modules, registry: registry, issues: issues)
  }
}
