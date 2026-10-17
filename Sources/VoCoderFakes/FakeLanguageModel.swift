import Synchronization
import VoCoderCore

/// A scripted language model. Queued outcomes are returned in order; with none queued, guided
/// generation fills the schema with placeholders (first choice, "fake", 0) and `respond` says
/// "Fake response.". Queued content that doesn't match the schema becomes `.decodingFailure`,
/// as in real adapters. `delay` simulates latency against the request's timeout.
public final class FakeLanguageModel: LanguageModel {
  public let id: ProviderID
  public let capabilities: LanguageModelCapabilities

  private struct State {
    var availability: LanguageModelAvailability
    var delay: Duration = .zero
    var guided: [GenerationOutcome<GeneratedContent>] = []
    var text: [GenerationOutcome<String>] = []
    var requests: [GenerationRequest] = []
    var prewarmCount = 0
  }

  private let state: Mutex<State>

  public init(
    id: ProviderID = "fake-model",
    capabilities: LanguageModelCapabilities = [.guidedGeneration, .tokenCounting],
    availability: LanguageModelAvailability = .available
  ) {
    self.id = id
    self.capabilities = capabilities
    self.state = Mutex(State(availability: availability))
  }

  // MARK: Scripting

  public func setAvailability(_ availability: LanguageModelAvailability) {
    state.withLock { $0.availability = availability }
  }

  public func setDelay(_ delay: Duration) { state.withLock { $0.delay = delay } }

  public func enqueue(_ outcome: GenerationOutcome<GeneratedContent>) {
    state.withLock { $0.guided.append(outcome) }
  }

  public func enqueueText(_ outcome: GenerationOutcome<String>) {
    state.withLock { $0.text.append(outcome) }
  }

  /// Requests received, in order.
  public var requests: [GenerationRequest] { state.withLock { $0.requests } }
  public var prewarmCount: Int { state.withLock { $0.prewarmCount } }

  // MARK: LanguageModel

  public func availability() async -> LanguageModelAvailability {
    state.withLock { $0.availability }
  }

  public func prewarm() async { state.withLock { $0.prewarmCount += 1 } }

  public func generate(_ request: GenerationRequest, schema: GenerationSchema) async
    -> GenerationOutcome<GeneratedContent>
  {
    guard capabilities.contains(.guidedGeneration) else { return .noParse(.unsupported) }
    guard
      let (delay, scripted) = begin(
        request, next: { $0.guided.isEmpty ? nil : $0.guided.removeFirst() })
    else { return .noParse(.unavailable) }
    return await withGenerationTimeout(request.timeout) {
      do { try await Task.sleep(for: delay) } catch { return .noParse(.timeout) }
      switch scripted {
      case .output(let content)?:
        return schema.validates(content) ? .output(content) : .noParse(.decodingFailure)
      case .noParse(let reason)?:
        return .noParse(reason)
      case nil:
        return .output(Self.placeholder(for: schema))
      }
    }
  }

  public func respond(to request: GenerationRequest) async -> GenerationOutcome<String> {
    guard
      let (delay, scripted) = begin(
        request, next: { $0.text.isEmpty ? nil : $0.text.removeFirst() })
    else { return .noParse(.unavailable) }
    return await withGenerationTimeout(request.timeout) {
      do { try await Task.sleep(for: delay) } catch { return .noParse(.timeout) }
      return scripted ?? .output("Fake response.")
    }
  }

  /// Roughly four characters per token.
  public func tokenCount(for text: String) async -> Int? {
    capabilities.contains(.tokenCounting) ? (text.utf8.count + 3) / 4 : nil
  }

  /// Records the request; nil when unavailable, else the delay and the next scripted outcome.
  private func begin<Outcome>(
    _ request: GenerationRequest, next: (inout State) -> Outcome?
  ) -> (Duration, Outcome?)? {
    state.withLock { state in
      state.requests.append(request)
      guard state.availability == .available else { return nil }
      return (state.delay, next(&state))
    }
  }

  private static func placeholder(for schema: GenerationSchema) -> GeneratedContent {
    var values: [String: GeneratedValue] = [:]
    for property in schema.properties where !property.isOptional {
      switch property.type {
      case .string: values[property.name] = .string("fake")
      case .integer: values[property.name] = .integer(0)
      case .choice(let choices): values[property.name] = choices.first.map { .string($0) }
      }
    }
    return GeneratedContent(values)
  }
}
