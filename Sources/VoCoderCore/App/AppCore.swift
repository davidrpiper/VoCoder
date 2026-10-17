/// The running app without its UI: loaded modules, app state, commands. `start()` opens the
/// contributed tabs and listens to attention sources; `stop()` undoes both. Core's built-in
/// commands (tabs) are registered before the modules' so a module can't take their ids.
@MainActor
public final class AppCore {
  public let state: AppState
  public let loaded: LoadedModules
  public let dispatcher: CommandDispatcher
  private let environment: ModuleEnvironment
  private var attentionTasks: [Task<Void, Never>] = []
  private let log = Log(category: "app")

  public init(loaded: LoadedModules, environment: ModuleEnvironment, state: AppState = AppState()) {
    self.loaded = loaded
    self.environment = environment
    self.state = state
    dispatcher = CommandDispatcher(state: state, registry: CommandRegistry(TabCommands.all))
    state.modules = loaded.moduleIDs
    state.report(loaded.issues)
    for id in dispatcher.register(loaded.registry.commands) {
      let module = loaded.registry.owner(of: id.rawValue, in: .commands) ?? "unknown"
      state.report(ModuleIssue(module: module, message: "command id '\(id)' is built in"))
    }
  }

  public var commands: CommandRegistry { dispatcher.registry }

  /// Adds app-level commands (the UI's navigation set); taken ids are reported as issues.
  public func register(_ commands: [Command], owner: ModuleID = "core") {
    for id in dispatcher.register(commands) {
      state.report(ModuleIssue(module: owner, message: "duplicate command id '\(id)'"))
    }
  }

  /// Loads `modules` and wraps them in a core (not yet started).
  public convenience init(modules: [any VoCoderModule.Type], environment: ModuleEnvironment) {
    self.init(
      loaded: ModuleLoader.load(modules, environment: environment), environment: environment)
  }

  public var registry: ModuleRegistry { loaded.registry }

  public func start() {
    openTabs()
    let now = environment.services.now
    for source in registry.attentionSources {
      let state = state
      attentionTasks.append(
        Task {
          for await item in source.items { state.post(item, now: now()) }
        })
    }
    log.info("started: \(state.tabs.count) tabs, \(commands.all.count) commands")
  }

  public func stop() {
    for task in attentionTasks { task.cancel() }
    attentionTasks = []
    state.closeAll()
  }

  /// Runs command `id` through the dispatcher.
  @discardableResult
  public func run(
    _ id: CommandID, arguments: CommandArguments = [:], source: CommandSource = .program
  ) async throws -> CommandOutcome {
    try await dispatcher.run(id, arguments: arguments, source: source)
  }

  /// Home, then repo, then integration tabs; registration order within each.
  private func openTabs() {
    let context = TabContext(repos: environment.repos)
    let factories = registry.tabFactories.enumerated().sorted {
      ($0.element.placement, $0.offset) < ($1.element.placement, $1.offset)
    }
    for factory in factories.map(\.element) {
      let module = registry.owner(of: factory.id.rawValue, in: .tabs) ?? "unknown"
      do {
        for tab in try factory.makeTabs(in: context) where !state.open(tab) {
          state.report(ModuleIssue(module: module, message: "duplicate tab id '\(tab.id)'"))
        }
      } catch {
        state.report(
          ModuleIssue(module: module, message: "tab factory \(factory.id) failed: \(error)"))
      }
    }
  }
}
