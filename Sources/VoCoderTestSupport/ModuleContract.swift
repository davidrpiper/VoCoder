import Testing
import VoCoderCore

/// Rules every module follows: a stable id, a clean start with an empty environment (no config,
/// no secrets — the app must start without accounts), no rejected contributions, tab
/// factories that make valid tabs with unique ids, and well-formed secret declarations.
/// Doctor checks run their own contract (`DoctorCheckContract`, async).
@MainActor
public enum ModuleContract {
  public static func verify(
    _ type: any VoCoderModule.Type, environment: ModuleEnvironment,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let id = type.id.rawValue
    let valid = !id.isEmpty && id == id.lowercased() && !id.contains { $0.isWhitespace }
    #expect(
      valid,
      "module id '\(id)' must be non-empty lower-case without spaces",
      sourceLocation: sourceLocation)

    let loaded = ModuleLoader.load([type], environment: environment)
    #expect(loaded.issues.isEmpty, "issues: \(loaded.issues)", sourceLocation: sourceLocation)
    #expect(loaded.moduleIDs == [type.id], sourceLocation: sourceLocation)

    let registry = loaded.registry
    for provider in providers(in: registry) {
      ProviderContract.verify(provider, sourceLocation: sourceLocation)
    }
    var tabIDs: Set<TabID> = []
    for factory in registry.tabFactories {
      do {
        let context = TabContext(
          repos: environment.repos, agents: registry.agents,
          sourceControl: registry.sourceControl, services: environment.services)
        for tab in try factory.makeTabs(in: context) {
          #expect(
            tabIDs.insert(tab.id).inserted, "duplicate tab id \(tab.id)",
            sourceLocation: sourceLocation)
          TabContract.verify(tab, sourceLocation: sourceLocation)
        }
      } catch {
        Issue.record("tab factory \(factory.id) threw \(error)", sourceLocation: sourceLocation)
      }
    }
    let secretNames = type.secrets.map(\.name)
    #expect(
      Set(secretNames).count == secretNames.count, "duplicate secret names",
      sourceLocation: sourceLocation)
    for spec in type.secrets {
      let valid = !spec.name.isEmpty && !spec.title.isEmpty && !spec.help.isEmpty
      #expect(
        valid, "secret '\(spec.name)' needs a name, title and help", sourceLocation: sourceLocation)
    }
    for command in registry.commands {
      #expect(
        !command.title.isEmpty, "command \(command.id) has no title", sourceLocation: sourceLocation
      )
    }
  }

  static func providers(in registry: ModuleRegistry) -> [any Provider] {
    var all: [any Provider] = []
    all += registry.agents as [any Provider]
    all += registry.trackers as [any Provider]
    all += registry.docs as [any Provider]
    all += registry.calendars as [any Provider]
    all += registry.chat as [any Provider]
    all += registry.sourceControl as [any Provider]
    all += registry.attentionSources as [any Provider]
    all += registry.brainTools as [any Provider]
    all += registry.activationSources as [any Provider]
    all += registry.speechRecognizers as [any Provider]
    all += registry.speechSynthesizers as [any Provider]
    all += registry.languageModels as [any Provider]
    all += registry.doctorChecks as [any Provider]
    return all
  }
}

/// Waits until `condition` holds (polling every millisecond), up to `timeout`. Returns whether
/// it held.
@MainActor
public func eventually(
  timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool
) async -> Bool {
  let deadline = ContinuousClock.now + timeout
  while !condition() {
    guard ContinuousClock.now < deadline else { return false }
    try? await Task.sleep(for: .milliseconds(1))
  }
  return true
}
