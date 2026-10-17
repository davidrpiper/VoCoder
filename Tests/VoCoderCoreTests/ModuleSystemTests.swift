import Foundation
import Testing
import VoCoderFakes
import VoCoderTestSupport

@testable import VoCoderCore

// Test modules. Static state is avoided: each type is its own fixture.

final class AcceptanceModule: VoCoderModule {
  static let id: ModuleID = "acceptance"
  let source = FakeAttentionSource(id: "acceptance-attention")

  init(context: ModuleContext) {}

  func register(into registry: inout ModuleRegistry) {
    registry.add(
      fakeTabs: .fake(id: "acceptance.tabs") { _ in
        [FakeTab(id: "acceptance.tab", title: "Acceptance", badge: .count(1))]
      })
    registry.add(commands: [
      Command(id: "acceptance.hello", title: "Say hello", category: "Test") { context in
        context.state.post(
          AttentionItem(id: "hello", source: "acceptance", priority: .soon, title: "Hello"))
      }
    ])
    registry.add(attentionSource: source)
    source.post("acceptance.item", title: "Look at me", priority: .interrupt)
  }
}

struct StartupError: Error, CustomStringConvertible {
  var description: String { "no network" }
}

final class FailingModule: VoCoderModule {
  static let id: ModuleID = "failing"
  init(context: ModuleContext) throws { throw StartupError() }
  func register(into registry: inout ModuleRegistry) {}
}

final class ImpostorModule: VoCoderModule {
  static let id: ModuleID = "acceptance"
  init(context: ModuleContext) {}
  func register(into registry: inout ModuleRegistry) {}
}

/// Registers a command id that `AcceptanceModule` already owns, and one of its own.
final class ClashingModule: VoCoderModule {
  static let id: ModuleID = "clashing"
  init(context: ModuleContext) {}
  func register(into registry: inout ModuleRegistry) {
    registry.add(commands: [
      Command(id: "acceptance.hello", title: "Imposter", category: "Test") { _ in },
      Command(id: "clashing.own", title: "Own", category: "Test") { _ in },
    ])
    registry.add(tracker: FakeTaskTracker(id: ""))
  }
}

struct GreetingConfig: ConfigSection, Equatable {
  var greeting: String
}

final class ConfiguredModule: VoCoderModule {
  static let id: ModuleID = "configured"
  static let configSection: (any ConfigSection.Type)? = GreetingConfig.self
  let config: GreetingConfig?
  let token: String?
  let now: Date

  init(context: ModuleContext) throws {
    config = context.config(GreetingConfig.self)
    token = try context.secrets.secret(for: SecretKey(module: Self.id, name: "token"))
    now = context.services.now()
  }

  func register(into registry: inout ModuleRegistry) {}
}

/// Factories registered out of placement order; one throws, one repeats a tab id.
final class TabsModule: VoCoderModule {
  static let id: ModuleID = "tabs"
  init(context: ModuleContext) {}
  func register(into registry: inout ModuleRegistry) {
    registry.add(
      fakeTabs: .fake(id: "tabs.integration", placement: .integration) { _ in
        [FakeTab(id: "integration")]
      })
    registry.add(
      fakeTabs: .fake(id: "tabs.broken", placement: .integration) { _ in
        throw StartupError()
      })
    registry.add(
      fakeTabs: .fake(id: "tabs.repos", placement: .repo) { context in
        context.repos.map { FakeTab(id: TabID("repo." + $0.name), title: $0.name) }
      })
    registry.add(
      fakeTabs: .fake(id: "tabs.home", placement: .home) { _ in
        [FakeTab(id: "home"), FakeTab(id: "integration")]
      })
  }
}

@MainActor
@Suite struct ModuleSystemTests {
  let environment = ModuleEnvironment(secrets: InMemorySecretStore())

  /// P1-04 acceptance: a fake module's tab, command and attention source appear.
  @Test func fakeModuleContributionsAppear() async throws {
    let core = AppCore(modules: [AcceptanceModule.self], environment: environment)
    core.start()
    defer { core.stop() }

    #expect(core.state.modules == ["acceptance"])
    #expect(core.state.issues.isEmpty)
    #expect(core.state.tabs.map(\.id) == ["acceptance.tab"])
    #expect(core.state.selectedTab?.title == "Acceptance")
    #expect(core.commands["acceptance.hello"]?.title == "Say hello")
    #expect(core.registry.attentionSources.map(\.id) == ["acceptance-attention"])
    #expect(await eventually { core.state.attention.map(\.id) == ["acceptance.item"] })
    #expect(core.state.attention.first?.priority == .interrupt)

    try await core.run("acceptance.hello")
    #expect(core.state.attention.map(\.id) == ["acceptance.item", "hello"])
  }

  @Test func failingModuleDoesNotStopOthers() {
    let core = AppCore(
      modules: [FailingModule.self, AcceptanceModule.self], environment: environment)
    #expect(core.state.modules == ["acceptance"])
    #expect(
      core.state.issues == [ModuleIssue(module: "failing", message: "failed to start: no network")])
  }

  @Test func duplicateModuleIDLoadsTheFirstOnly() {
    let loaded = ModuleLoader.load(
      [AcceptanceModule.self, ImpostorModule.self], environment: environment)
    #expect(loaded.modules.count == 1)
    #expect(loaded.modules.first is AcceptanceModule)
    #expect(loaded.issues.map(\.module) == ["acceptance"])
  }

  @Test func onlyEnabledModulesLoad() {
    var environment = environment
    environment.enabled = ["configured"]
    let loaded = ModuleLoader.load(
      [AcceptanceModule.self, ConfiguredModule.self], environment: environment)
    #expect(loaded.moduleIDs == ["configured"])
    #expect(loaded.issues.isEmpty)
  }

  @Test func duplicateContributionsAreRejectedAndAttributed() {
    let loaded = ModuleLoader.load(
      [AcceptanceModule.self, ClashingModule.self], environment: environment)
    let registry = loaded.registry
    #expect(registry.commands.map(\.id) == ["acceptance.hello", "clashing.own"])
    #expect(registry.commands.first?.title == "Say hello")
    #expect(registry.owner(of: "acceptance.hello", in: .commands) == "acceptance")
    #expect(registry.owner(of: "clashing.own", in: .commands) == "clashing")
    #expect(registry.trackers.isEmpty)
    #expect(
      loaded.issues == [
        ModuleIssue(
          module: "clashing",
          message: "commands: id 'acceptance.hello' is already registered by acceptance"),
        ModuleIssue(module: "clashing", message: "empty id in trackers"),
      ])
  }

  @Test func contextCarriesConfigSecretsAndServices() throws {
    let secrets = InMemorySecretStore([SecretKey(module: "configured", name: "token"): "s3cret"])
    var services = ServiceContainer()
    let fixed = Date(timeIntervalSince1970: 1_000)
    services.now = { fixed }
    var requested: [ModuleID] = []
    let environment = ModuleEnvironment(secrets: secrets, services: services) { module, type in
      requested.append(module)
      #expect(type is GreetingConfig.Type)
      return GreetingConfig(greeting: "hi")
    }
    let loaded = ModuleLoader.load(
      [ConfiguredModule.self, AcceptanceModule.self], environment: environment)
    let module = try #require(loaded.modules.first as? ConfiguredModule)
    #expect(module.config == GreetingConfig(greeting: "hi"))
    #expect(module.token == "s3cret")
    #expect(module.now == fixed)
    #expect(requested == ["configured"], "modules without a section aren't asked for one")
  }

  @Test func invalidConfigSectionFailsTheModule() {
    let environment = ModuleEnvironment(secrets: InMemorySecretStore()) { _, _ in
      throw StartupError()
    }
    let loaded = ModuleLoader.load([ConfiguredModule.self], environment: environment)
    #expect(loaded.modules.isEmpty)
    #expect(loaded.issues.map(\.module) == ["configured"])
  }

  @Test func tabsOpenByPlacementAndFactoryProblemsAreReported() {
    var environment = environment
    environment.repos = [
      RepoRoot(url: URL(filePath: "/src/alpha")), RepoRoot(url: URL(filePath: "/src/beta")),
    ]
    let core = AppCore(modules: [TabsModule.self], environment: environment)
    core.start()
    #expect(core.state.tabs.map(\.id) == ["home", "integration", "repo.alpha", "repo.beta"])
    #expect(core.state.selectedTabID == "home")
    #expect(
      core.state.issues == [
        ModuleIssue(module: "tabs", message: "duplicate tab id 'integration'"),
        ModuleIssue(module: "tabs", message: "tab factory tabs.broken failed: no network"),
      ])
    core.stop()
    #expect(core.state.tabs.isEmpty)
  }

  @Test func builtInTabsOpenFirstWithinTheirPlacement() {
    let builtIn = TabFactory.fake(id: "core.home", placement: .home) { _ in
      [FakeTab(id: "core-home", title: "Home")]
    }
    let core = AppCore(modules: [TabsModule.self], environment: environment, builtInTabs: [builtIn])
    core.start()
    #expect(core.state.tabs.map(\.id) == ["core-home", "home", "integration"])
    #expect(core.state.selectedTabID == "core-home")
    core.stop()
  }

  @Test func stopClosesTabsAndStopsListening() async {
    let core = AppCore(modules: [AcceptanceModule.self], environment: environment)
    core.start()
    let tab = core.state.tabs.first as? FakeTab
    #expect(await eventually { core.state.attention.count == 1 })
    core.stop()
    #expect(tab?.lifecycle == ["activate", "deactivate", "close"])
    let source = core.loaded.modules.first.flatMap { $0 as? AcceptanceModule }?.source
    source?.post("late", title: "Too late")
    try? await Task.sleep(for: .milliseconds(20))
    #expect(core.state.attention.map(\.id) == ["acceptance.item"])
  }

  @Test func unknownCommandThrows() async {
    let core = AppCore(modules: [], environment: environment)
    await #expect(throws: CommandError.unknown("nope")) { try await core.run("nope") }
  }
}
