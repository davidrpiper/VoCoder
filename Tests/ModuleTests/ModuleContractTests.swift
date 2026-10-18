import ClaudeCodeModule
import DemoModule
import EventKitCalendarModule
import GitModule
import LinearModule
import NotionModule
import RepoModule
import Testing
import VoCoderCore
import VoCoderFakes
import VoCoderTestSupport

/// Every module target runs the module contract. Add new modules here as well as to
/// `CompiledModules` in the executable.
@MainActor
@Suite struct ModuleContractTests {
  static let modules: [any VoCoderModule.Type] = [
    GitModule.self, ClaudeCodeModule.self, RepoModule.self, EventKitCalendarModule.self,
    LinearModule.self, NotionModule.self, DemoModule.self,
  ]

  @Test func everyModulePassesTheContract() {
    for module in Self.modules {
      ModuleContract.verify(module, environment: ModuleEnvironment(secrets: InMemorySecretStore()))
    }
  }

  /// With repos (and the demo's fake agent and git), the repo module makes one tab each.
  @Test func repoModuleMakesValidRepoTabs() {
    let environment = ModuleEnvironment(secrets: InMemorySecretStore(), repos: DemoModule.repos)
    ModuleContract.verify(RepoModule.self, environment: environment)
    let loaded = ModuleLoader.load([DemoModule.self, RepoModule.self], environment: environment)
    #expect(loaded.issues.isEmpty)
    #expect(loaded.registry.tabFactories.map(\.id) == ["demo.tasks", "repo.tabs"])
  }

  @Test func moduleIDsAreUnique() {
    #expect(Set(Self.modules.map { $0.id }).count == Self.modules.count)
  }

  @Test func allModulesLoadTogether() {
    let loaded = ModuleLoader.load(
      Self.modules, environment: ModuleEnvironment(secrets: InMemorySecretStore()))
    #expect(loaded.issues.isEmpty)
    #expect(loaded.modules.count == Self.modules.count)
  }
}
