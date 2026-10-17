import Foundation
import Testing
import VoCoderFakes
import VoCoderTestSupport

@testable import VoCoderCore

/// Every fake passes its protocol's contract suite.
@MainActor
@Suite struct FakeContractTests {
  @Test func providers() {
    let providers: [any Provider] = [
      FakeAgentBackend(), FakeDocsProvider(), FakeCalendarProvider(), FakeChatProvider(),
      FakeBrainTool(), FakeActivationSource(), FakeSpeechRecognizer(), FakeSpeechSynthesizer(),
    ]
    for provider in providers { ProviderContract.verify(provider) }
    TaskTrackerContract.verify(FakeTaskTracker(capabilities: [.iterations, .subtasks]))
  }

  @Test func attentionSource() async {
    let source = FakeAttentionSource()
    await AttentionSourceContract.verify(source) { source.post("x", title: "Something") }
  }

  @Test func secretStore() throws {
    try SecretStoreContract.verify(InMemorySecretStore())
  }

  @Test func tab() {
    let tab = FakeTab(id: "t", title: "T")
    TabContract.verify(tab)
    #expect(tab.lifecycle == ["activate", "deactivate", "activate", "deactivate", "close"])
  }

  @Test(arguments: [
    FakeLanguageModel(),
    FakeLanguageModel(capabilities: []),
    FakeLanguageModel(availability: .unavailable("off")),
  ])
  func languageModel(_ model: FakeLanguageModel) async {
    await LanguageModelContract.verify(model)
  }

  @Test func moduleContractCatchesProblems() {
    let environment = ModuleEnvironment(secrets: InMemorySecretStore())
    ModuleContract.verify(AcceptanceModule.self, environment: environment)
    withKnownIssue {
      ModuleContract.verify(ClashingModule.self, environment: environment)
    }
  }
}

@Suite struct RegistryTests {
  @Test func commandRegistryKeepsTheFirstOfDuplicateIDs() {
    var registry = CommandRegistry()
    let first = registry.register(Command(id: "a", title: "A", category: "") { _ in })
    let second = registry.register(Command(id: "a", title: "A2", category: "") { _ in })
    #expect(first && !second)
    #expect(registry.all.map(\.title) == ["A"])
    #expect(registry["a"]?.title == "A")
    #expect(registry["b"] == nil)
  }

  @Test func serviceContainerFallsBackToDefaults() {
    var services = ServiceContainer()
    #expect(abs(services.now().timeIntervalSinceNow) < 5)
    let fixed = Date(timeIntervalSince1970: 0)
    services.now = { fixed }
    #expect(services.now() == fixed)
  }

  @Test func identifiersAreTypedStrings() {
    let id: CommandID = "agent.approve"
    #expect(id.description == "agent.approve")
    #expect(CommandID("a") < CommandID("b"))
    #expect(Set<TabID>(["x", "x", "y"]).count == 2)
  }
}
