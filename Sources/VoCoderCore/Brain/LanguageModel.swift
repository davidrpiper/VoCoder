// The language-model seam (DESIGN §4.6, ADR 0003). Vendor-neutral: the Foundation Models
// adapter (P2-05) maps the schema to a `DynamicGenerationSchema`, the Claude adapter (P3-02) to
// a JSON-schema tool. Model errors are outcomes, never thrown: voice must not stall or surface
// guardrail noise, so every failure is a typed "no parse".

/// Whether the model can be used right now.
public enum LanguageModelAvailability: Sendable, Equatable {
  case available
  /// With a reason a user can act on ("Apple Intelligence is turned off").
  case unavailable(String)
}

public struct LanguageModelCapabilities: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  /// `generate(_:schema:)` is supported (otherwise it returns `.noParse(.unsupported)`).
  public static let guidedGeneration = LanguageModelCapabilities(rawValue: 1 << 0)
  /// `tokenCount(for:)` returns counts (input budgeting for summaries).
  public static let tokenCounting = LanguageModelCapabilities(rawValue: 1 << 1)
}

/// Why a call produced nothing usable. All of these mean "no parse" to the router.
public enum NoParseReason: Sendable, Equatable {
  case unavailable
  case unsupported
  case timeout
  case guardrail
  case refusal
  /// Output didn't decode, or didn't match the schema.
  case decodingFailure
  case contextOverflow
}

public enum GenerationOutcome<Output: Sendable>: Sendable {
  case output(Output)
  case noParse(NoParseReason)

  public var value: Output? {
    if case .output(let output) = self { output } else { nil }
  }
}

extension GenerationOutcome: Equatable where Output: Equatable {}

/// One model call. Sampling is greedy (deterministic routing, ADR 0003).
public struct GenerationRequest: Sendable, Equatable {
  public var instructions: String
  public var prompt: String
  /// Hard limit; past it the call returns `.noParse(.timeout)`.
  public var timeout: Duration
  public var maxResponseTokens: Int?

  public init(
    instructions: String, prompt: String, timeout: Duration = .milliseconds(1500),
    maxResponseTokens: Int? = nil
  ) {
    self.instructions = instructions
    self.prompt = prompt
    self.timeout = timeout
    self.maxResponseTokens = maxResponseTokens
  }
}

/// A flat object schema for guided generation: the intent shape of ADR 0003 (a `kind` choice
/// plus optional typed slots), generated per context from the available commands.
public struct GenerationSchema: Sendable, Equatable {
  public enum PropertyType: Sendable, Equatable {
    case string
    case integer
    /// One of these exact strings.
    case choice([String])
  }

  public struct Property: Sendable, Equatable {
    public let name: String
    public let description: String
    public let type: PropertyType
    public let isOptional: Bool

    public init(_ name: String, _ type: PropertyType, description: String, optional: Bool = false) {
      self.name = name
      self.description = description
      self.type = type
      self.isOptional = optional
    }
  }

  public let name: String
  public let description: String
  public let properties: [Property]

  public init(name: String, description: String, properties: [Property]) {
    self.name = name
    self.description = description
    self.properties = properties
  }

  /// Whether `content` has every required property, no unknown ones, and values of the
  /// declared types (choices from their list). Adapters return `.decodingFailure` otherwise.
  public func validates(_ content: GeneratedContent) -> Bool {
    let known = Set(properties.map(\.name))
    guard content.values.keys.allSatisfy(known.contains) else { return false }
    return properties.allSatisfy { property in
      switch (property.type, content.values[property.name]) {
      case (_, nil): property.isOptional
      case (.string, .string?), (.integer, .integer?): true
      case (.choice(let choices), .string(let value)?): choices.contains(value)
      default: false
      }
    }
  }
}

public enum GeneratedValue: Sendable, Equatable {
  case string(String)
  case integer(Int)
}

/// Guided-generation output: property name → value (absent optional properties are missing).
public struct GeneratedContent: Sendable, Equatable {
  public var values: [String: GeneratedValue]

  public init(_ values: [String: GeneratedValue]) { self.values = values }

  public subscript(name: String) -> GeneratedValue? { values[name] }

  public func string(_ name: String) -> String? {
    if case .string(let value)? = values[name] { value } else { nil }
  }

  public func integer(_ name: String) -> Int? {
    if case .integer(let value)? = values[name] { value } else { nil }
  }
}

/// A model behind the brain: Foundation Models on device, Claude via the API.
public protocol LanguageModel: Provider {
  var capabilities: LanguageModelCapabilities { get }

  func availability() async -> LanguageModelAvailability
  /// Loads the model ahead of a likely call (voice activation). Cheap if already warm.
  func prewarm() async
  /// Guided generation into `schema`. Honours `request.timeout`.
  func generate(_ request: GenerationRequest, schema: GenerationSchema) async
    -> GenerationOutcome<GeneratedContent>
  /// Free text (summaries, briefings), capped by `request.maxResponseTokens`.
  func respond(to request: GenerationRequest) async -> GenerationOutcome<String>
  /// Tokens `text` takes in this model's context; nil without `.tokenCounting`.
  func tokenCount(for text: String) async -> Int?
}

/// Runs `operation`, returning `.noParse(.timeout)` if it takes longer than `timeout`. The
/// operation is cancelled then and must honour cancellation (this waits for it to return).
public func withGenerationTimeout<Output: Sendable>(
  _ timeout: Duration, _ operation: @escaping @Sendable () async -> GenerationOutcome<Output>
) async -> GenerationOutcome<Output> {
  await withTaskGroup(of: GenerationOutcome<Output>.self) { group in
    group.addTask { await operation() }
    group.addTask {
      try? await Task.sleep(for: timeout)
      return .noParse(.timeout)
    }
    let first = await group.next() ?? .noParse(.timeout)
    group.cancelAll()
    return first
  }
}
