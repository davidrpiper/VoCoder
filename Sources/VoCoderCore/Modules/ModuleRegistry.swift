/// The extension points of DESIGN §4.10, named for messages and lookups.
public enum ExtensionPoint: String, Sendable, CaseIterable {
  case agents, trackers, docs, calendars, chat, tabs, commands, workflows, attention
  case sourceControl = "source control"
  case brainTools = "brain tools"
  case activation
  case speechRecognizers = "speech recognizers"
  case speechSynthesizers = "speech synthesizers"
  case languageModels = "language models"
  case doctorChecks = "doctor checks"
}

/// Everything the enabled modules contributed, in registration order. Ids are unique per
/// extension point: a duplicate is rejected and recorded as an issue of the module that tried
/// to add it (first registration wins).
@MainActor
public struct ModuleRegistry {
  public private(set) var agents: [any AgentBackend] = []
  public private(set) var trackers: [any TaskTracker] = []
  public private(set) var docs: [any DocsProvider] = []
  public private(set) var calendars: [any CalendarProvider] = []
  public private(set) var chat: [any ChatProvider] = []
  public private(set) var sourceControl: [any SourceControl] = []
  public private(set) var tabFactories: [TabFactory] = []
  public private(set) var commands: [Command] = []
  public private(set) var workflows: [any Workflow] = []
  public private(set) var attentionSources: [any AttentionSource] = []
  public private(set) var brainTools: [any BrainTool] = []
  public private(set) var activationSources: [any ActivationSource] = []
  public private(set) var speechRecognizers: [any SpeechRecognizer] = []
  public private(set) var speechSynthesizers: [any SpeechSynthesizer] = []
  public private(set) var languageModels: [any LanguageModel] = []
  public private(set) var doctorChecks: [any DoctorCheck] = []

  /// Rejected contributions.
  public private(set) var issues: [ModuleIssue] = []
  /// The module whose `register(into:)` is running; contributions are attributed to it.
  public internal(set) var currentModule: ModuleID
  private var owners: [Key: ModuleID] = [:]

  private struct Key: Hashable {
    let point: ExtensionPoint
    let id: String
  }

  public init(module: ModuleID = "core") { currentModule = module }

  /// Which module contributed `id` to `point`.
  public func owner(of id: String, in point: ExtensionPoint) -> ModuleID? {
    owners[Key(point: point, id: id)]
  }

  public mutating func add(agent: any AgentBackend) {
    add(agent, id: agent.id.rawValue, to: .agents, at: \.agents)
  }
  public mutating func add(tracker: any TaskTracker) {
    add(tracker, id: tracker.id.rawValue, to: .trackers, at: \.trackers)
  }
  public mutating func add(docs provider: any DocsProvider) {
    add(provider, id: provider.id.rawValue, to: .docs, at: \.docs)
  }
  public mutating func add(calendar: any CalendarProvider) {
    add(calendar, id: calendar.id.rawValue, to: .calendars, at: \.calendars)
  }
  public mutating func add(chat provider: any ChatProvider) {
    add(provider, id: provider.id.rawValue, to: .chat, at: \.chat)
  }
  public mutating func add(sourceControl provider: any SourceControl) {
    add(provider, id: provider.id.rawValue, to: .sourceControl, at: \.sourceControl)
  }
  /// Modules use `add(tabs:)` from `VoCoderUI`, which only takes factories of drawable tabs.
  package mutating func add(tabFactory: TabFactory) {
    add(tabFactory, id: tabFactory.id.rawValue, to: .tabs, at: \.tabFactories)
  }
  public mutating func add(commands: [Command]) {
    for command in commands { add(command, id: command.id.rawValue, to: .commands, at: \.commands) }
  }
  public mutating func add(workflow: any Workflow) {
    add(workflow, id: workflow.id.rawValue, to: .workflows, at: \.workflows)
  }
  public mutating func add(attentionSource: any AttentionSource) {
    add(attentionSource, id: attentionSource.id.rawValue, to: .attention, at: \.attentionSources)
  }
  public mutating func add(brainTool: any BrainTool) {
    add(brainTool, id: brainTool.id.rawValue, to: .brainTools, at: \.brainTools)
  }
  public mutating func add(activationSource: any ActivationSource) {
    add(
      activationSource, id: activationSource.id.rawValue, to: .activation, at: \.activationSources)
  }
  public mutating func add(speechRecognizer: any SpeechRecognizer) {
    add(
      speechRecognizer, id: speechRecognizer.id.rawValue, to: .speechRecognizers,
      at: \.speechRecognizers)
  }
  public mutating func add(speechSynthesizer: any SpeechSynthesizer) {
    add(
      speechSynthesizer, id: speechSynthesizer.id.rawValue, to: .speechSynthesizers,
      at: \.speechSynthesizers)
  }
  public mutating func add(languageModel: any LanguageModel) {
    add(languageModel, id: languageModel.id.rawValue, to: .languageModels, at: \.languageModels)
  }

  public mutating func add(doctorCheck: any DoctorCheck) {
    add(doctorCheck, id: doctorCheck.id.rawValue, to: .doctorChecks, at: \.doctorChecks)
  }

  private mutating func add<Value>(
    _ value: Value, id: String, to point: ExtensionPoint,
    at list: WritableKeyPath<ModuleRegistry, [Value]>
  ) {
    let key = Key(point: point, id: id)
    if id.isEmpty {
      issues.append(ModuleIssue(module: currentModule, message: "empty id in \(point.rawValue)"))
    } else if let owner = owners[key] {
      issues.append(
        ModuleIssue(
          module: currentModule,
          message: "\(point.rawValue): id '\(id)' is already registered by \(owner)"))
    } else {
      owners[key] = currentModule
      self[keyPath: list].append(value)
    }
  }
}
