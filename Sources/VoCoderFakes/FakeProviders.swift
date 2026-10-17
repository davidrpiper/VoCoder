// In-memory fakes of the Core protocols (DESIGN §4.10 "fakes first"): used by tests, snapshot
// fixtures and `vocoder --demo`. Each one passes its contract suite in `VoCoderTestSupport`.
import Synchronization
import VoCoderCore

public struct FakeAgentBackend: AgentBackend {
  public let id: ProviderID
  public init(id: ProviderID = "fake-agent") { self.id = id }
}

public struct FakeTaskTracker: TaskTracker {
  public let id: ProviderID
  public let capabilities: TaskTrackerCapabilities

  public init(id: ProviderID = "fake-tracker", capabilities: TaskTrackerCapabilities = []) {
    self.id = id
    self.capabilities = capabilities
  }
}

public struct FakeDocsProvider: DocsProvider {
  public let id: ProviderID
  public init(id: ProviderID = "fake-docs") { self.id = id }
}

public struct FakeCalendarProvider: CalendarProvider {
  public let id: ProviderID
  public init(id: ProviderID = "fake-calendar") { self.id = id }
}

public struct FakeChatProvider: ChatProvider {
  public let id: ProviderID
  public init(id: ProviderID = "fake-chat") { self.id = id }
}

public struct FakeWorkflow: Workflow {
  public let id: WorkflowID
  public let title: String

  public init(id: WorkflowID = "fake.workflow", title: String = "Fake workflow") {
    self.id = id
    self.title = title
  }
}

public struct FakeBrainTool: BrainTool {
  public let id: ProviderID
  public init(id: ProviderID = "fake-tool") { self.id = id }
}

public struct FakeActivationSource: ActivationSource {
  public let id: ProviderID
  public init(id: ProviderID = "fake-activation") { self.id = id }
}

public struct FakeSpeechRecognizer: SpeechRecognizer {
  public let id: ProviderID
  public init(id: ProviderID = "fake-recognizer") { self.id = id }
}

public struct FakeSpeechSynthesizer: SpeechSynthesizer {
  public let id: ProviderID
  public init(id: ProviderID = "fake-synthesizer") { self.id = id }
}

/// An attention source fed by hand: `post` emits an item stamped with this source's id.
public final class FakeAttentionSource: AttentionSource {
  public let id: ProviderID
  public let items: AsyncStream<AttentionItem>
  private let continuation: AsyncStream<AttentionItem>.Continuation

  public init(id: ProviderID = "fake-attention") {
    self.id = id
    (items, continuation) = AsyncStream.makeStream()
  }

  public func post(_ item: AttentionItem) { continuation.yield(item) }

  /// Emits a new item from this source.
  public func post(
    _ id: AttentionItemID, title: String, priority: AttentionPriority = .ambient
  ) {
    post(AttentionItem(id: id, source: self.id, priority: priority, title: title))
  }

  public func finish() { continuation.finish() }
}

/// A secret store in memory (tests, demo, and until the Keychain store in P1-06).
public final class InMemorySecretStore: SecretStore {
  private let secrets: Mutex<[SecretKey: String]>

  public init(_ secrets: [SecretKey: String] = [:]) { self.secrets = Mutex(secrets) }

  public func secret(for key: SecretKey) throws -> String? { secrets.withLock { $0[key] } }

  public func setSecret(_ value: String, for key: SecretKey) throws {
    secrets.withLock { $0[key] = value }
  }

  public func removeSecret(for key: SecretKey) throws {
    secrets.withLock { _ = $0.removeValue(forKey: key) }
  }
}

/// A doctor check with a fixed result.
public struct FakeDoctorCheck: DoctorCheck {
  public let id: ProviderID
  public let title: String
  public let result: DoctorResult

  public init(
    id: ProviderID = "fake-check", title: String = "Fake check",
    result: DoctorResult = .ok("fine")
  ) {
    self.id = id
    self.title = title
    self.result = result
  }

  public func run() async -> DoctorResult { result }
}
