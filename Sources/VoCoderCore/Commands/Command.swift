// The command registry (DESIGN §2.1). Every user-facing action is one of these; keys, the leader
// popup, the palette, voice and the brain all run them through the `CommandDispatcher`
// (ADR 0007).

/// How careful the app is before running a command (DESIGN §3.4).
public enum RiskTier: Int, Sendable, Comparable, CaseIterable {
  /// Navigate, read, summarise: just do it.
  case readOnly
  /// Change an issue status, mark read: do it, then offer undo.
  case reversible
  /// Post a comment, git push, approve an agent's shell command: read back and confirm.
  case outward

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where a command invocation came from.
public enum CommandSource: String, Sendable {
  case key, palette, voice, brain
  /// Tests and app code (e.g. the dev shell's command list).
  case program
}

/// A user-facing action. Keys, palette, voice and the brain all dispatch through these.
public struct Command: Identifiable, Sendable {
  /// Runs the command. It reports a spoken result or an undo through the context
  /// (`say(_:)`, `offerUndo(_:)`).
  public typealias Perform = @MainActor @Sendable (CommandContext) async throws -> Void
  public typealias Availability = @MainActor @Sendable (CommandContext) -> Bool

  public let id: CommandID
  public let title: String
  /// Palette / help grouping ("Tabs", "Agent", "Demo").
  public let category: String
  /// Default key bindings; config can replace them (`KeyBindingOverrides`).
  public let keys: [KeyBinding]
  /// Fixed phrases for the voice grammar (P2-05), e.g. "next tab".
  public let voicePhrases: [String]
  /// Asked for in order when missing (the palette prompts; voice fills slots).
  public let params: [CommandParameter]
  public let risk: RiskTier
  /// Whether the command makes sense in a context (the focused tab, the focused item). An
  /// unavailable command is hidden from the palette and help, and its keys fall through.
  public let isAvailable: Availability
  public let perform: Perform

  public init(
    id: CommandID, title: String, category: String, keys: [KeyBinding] = [],
    voicePhrases: [String] = [], params: [CommandParameter] = [], risk: RiskTier = .readOnly,
    isAvailable: @escaping Availability = { _ in true },
    perform: @escaping Perform
  ) {
    self.id = id
    self.title = title
    self.category = category
    self.keys = keys
    self.voicePhrases = voicePhrases
    self.params = params
    self.risk = risk
    self.isAvailable = isAvailable
    self.perform = perform
  }
}

/// What running a command produced.
public struct CommandOutcome: Sendable {
  /// Said after the command ran (voice); nil says nothing beyond the earcon.
  public var spoken: String?
  /// How to take it back (reversible commands); handed to the dispatcher's `UndoSink`.
  public var undo: UndoAction?

  public init(spoken: String? = nil, undo: UndoAction? = nil) {
    self.spoken = spoken
    self.undo = undo
  }

  public static let done = CommandOutcome()
}

/// Takes back what a command did. The undo window and its voice/keys flow are P2-07.
public struct UndoAction: Sendable {
  /// "Move ENG-123 back to Todo".
  public let title: String
  public let perform: @MainActor @Sendable () async throws -> Void

  public init(title: String, perform: @escaping @MainActor @Sendable () async throws -> Void) {
    self.title = title
    self.perform = perform
  }
}

/// The keyboard focus as plain ids (the UI's `FocusID`s), so Core commands can depend on what
/// is focused without importing the UI. The voice cursor is the same focus (DESIGN §2.2).
public struct FocusSnapshot: Sendable, Equatable {
  /// The focused leaf.
  public var focused: String?
  /// Scopes containing the focused leaf, outermost first, then the leaf.
  public var path: [String]

  public init(focused: String? = nil, path: [String] = []) {
    self.focused = focused
    self.path = path
  }

  public static let none = FocusSnapshot()

  /// Whether `id` is the focused leaf or one of its scopes.
  public func contains(_ id: String) -> Bool { path.contains(id) }
}

/// What a command runs against, and where it leaves its outcome.
@MainActor
public struct CommandContext {
  public let state: AppState
  public let focus: FocusSnapshot
  public let arguments: CommandArguments
  public let source: CommandSource
  /// Questions and notices for the user while the command runs (modals and toasts, later voice).
  public let prompter: any CommandPrompter
  private let result: OutcomeBox

  public init(
    state: AppState, focus: FocusSnapshot = .none, arguments: CommandArguments = [:],
    source: CommandSource = .program, prompter: (any CommandPrompter)? = nil
  ) {
    self.init(
      state: state, focus: focus, arguments: arguments, source: source,
      prompter: prompter ?? DecliningPrompter.shared, result: OutcomeBox())
  }

  private init(
    state: AppState, focus: FocusSnapshot, arguments: CommandArguments, source: CommandSource,
    prompter: any CommandPrompter, result: OutcomeBox
  ) {
    self.state = state
    self.focus = focus
    self.arguments = arguments
    self.source = source
    self.prompter = prompter
    self.result = result
  }

  public var selectedTab: (any Tab)? { state.selectedTab }

  /// What to say when the command is done (voice). The last call wins.
  public func say(_ text: String) { result.outcome.spoken = text }

  /// How to take the command back (reversible commands).
  public func offerUndo(_ undo: UndoAction) { result.outcome.undo = undo }

  /// What `say` and `offerUndo` recorded.
  public var outcome: CommandOutcome { result.outcome }

  /// A fresh context (and outcome) with `arguments`.
  func with(arguments: CommandArguments) -> CommandContext {
    CommandContext(
      state: state, focus: focus, arguments: arguments, source: source, prompter: prompter)
  }
}

@MainActor
private final class OutcomeBox {
  var outcome = CommandOutcome()
}

/// All registered commands, in registration order, unique by id.
public struct CommandRegistry: Sendable {
  public private(set) var all: [Command] = []
  private var indices: [CommandID: Int] = [:]

  public init() {}

  public init(_ commands: [Command]) {
    for command in commands where indices[command.id] == nil { append(command) }
  }

  public subscript(id: CommandID) -> Command? { indices[id].map { all[$0] } }

  /// Registration order, for stable sorting.
  public func index(of id: CommandID) -> Int? { indices[id] }

  /// Adds `command`; returns false (and adds nothing) when its id is taken.
  @discardableResult
  public mutating func register(_ command: Command) -> Bool {
    guard indices[command.id] == nil else { return false }
    append(command)
    return true
  }

  /// Puts `commands` first, removing registered commands with the same ids (built-ins win over
  /// modules). Returns the removed commands.
  @discardableResult
  public mutating func prepend(_ commands: [Command]) -> [Command] {
    let ids = Set(commands.map(\.id))
    let removed = all.filter { ids.contains($0.id) }
    let rest = all.filter { !ids.contains($0.id) }
    all = []
    indices = [:]
    for command in commands + rest where indices[command.id] == nil { append(command) }
    return removed
  }

  private mutating func append(_ command: Command) {
    indices[command.id] = all.count
    all.append(command)
  }
}

public enum CommandError: Error, Equatable, CustomStringConvertible {
  case unknown(CommandID)
  /// Its availability predicate is false in this context.
  case unavailable(CommandID)
  case missingArgument(CommandID, parameter: String)
  case invalidArgument(CommandID, parameter: String)
  /// An outward command the confirmer (or the default policy) declined.
  case declined(CommandID)

  public var description: String {
    switch self {
    case .unknown(let id): "unknown command \(id)"
    case .unavailable(let id): "\(id) isn't available here"
    case .missingArgument(let id, let name): "\(id) needs '\(name)'"
    case .invalidArgument(let id, let name): "\(id): invalid '\(name)'"
    case .declined(let id): "\(id) was not confirmed"
    }
  }
}
