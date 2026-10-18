// Repo tabs (DESIGN §3.2, ADR 0013): one per configured repo root, built on whichever agent
// backend and source control the other modules registered. It never imports those modules.
import VoCoderCore
import VoCoderUI

public final class RepoModule: VoCoderModule {
  public static let id: ModuleID = "repo"

  public init(context: ModuleContext) {}

  public func register(into registry: inout ModuleRegistry) {
    registry.add(
      tabs: TabFactory(id: "repo.tabs", placement: .repo) { context in
        context.repos.map { root in
          RepoTab(
            root: root, agent: context.agents.first, sourceControl: context.sourceControl.first,
            services: context.services)
        }
      })
    registry.add(commands: RepoCommands.all)
  }
}
