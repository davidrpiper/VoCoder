/// Asked before an outward command runs (DESIGN §3.4). P1-07 supplies a dialog for keys and the
/// palette; P2-07 the spoken read-back and "confirm".
@MainActor
public protocol CommandConfirmer: AnyObject {
  func confirm(_ command: Command, in context: CommandContext) async -> Bool
}

/// Receives undo actions from reversible commands. P2-07 implements the "say undo within 5
/// seconds" window on top.
@MainActor
public protocol UndoSink: AnyObject {
  func register(_ undo: UndoAction, for command: Command)
}

/// Runs commands: builds the context (state, focus, arguments, source), checks availability and
/// arguments, asks for confirmation when the risk tier needs it, runs, and hands undo actions
/// on. Every front-end (keys, palette, voice, brain) goes through here.
@MainActor
public final class CommandDispatcher {
  public private(set) var registry: CommandRegistry
  public let state: AppState
  /// The UI's focus; Core has none of its own.
  public var focusProvider: @MainActor () -> FocusSnapshot = { .none }
  /// Without one, outward commands run only when chosen explicitly (keys, palette, program);
  /// from voice or the brain they are declined.
  public weak var confirmer: (any CommandConfirmer)?
  public weak var undoSink: (any UndoSink)?
  /// Most recently run first (palette ranking).
  public private(set) var recent: [CommandID] = []
  private let log = Log(category: "commands")

  public init(state: AppState, registry: CommandRegistry = CommandRegistry()) {
    self.state = state
    self.registry = registry
  }

  /// Adds `commands`; returns the ids that were already taken (and were not added).
  @discardableResult
  public func register(_ commands: [Command]) -> [CommandID] {
    commands.filter { !registry.register($0) }.map(\.id)
  }

  /// Adds app built-ins ahead of everything registered so far; a module command with the same
  /// id is removed and returned.
  @discardableResult
  public func registerBuiltIns(_ commands: [Command]) -> [Command] {
    registry.prepend(commands)
  }

  public subscript(id: CommandID) -> Command? { registry[id] }

  public func context(
    source: CommandSource = .program, arguments: CommandArguments = [:]
  ) -> CommandContext {
    CommandContext(state: state, focus: focusProvider(), arguments: arguments, source: source)
  }

  public func isAvailable(_ id: CommandID, source: CommandSource = .program) -> Bool {
    guard let command = registry[id] else { return false }
    return command.isAvailable(context(source: source))
  }

  /// Commands available now, in registration order.
  public func available(source: CommandSource = .program) -> [Command] {
    let context = context(source: source)
    return registry.all.filter { $0.isAvailable(context) }
  }

  /// Required parameters `arguments` doesn't supply, in order.
  public func missingParameters(of id: CommandID, given arguments: CommandArguments = [:])
    -> [CommandParameter]
  {
    registry[id]?.params.filter { !$0.isOptional && arguments[$0.name] == nil } ?? []
  }

  /// Runs `id`. Throws `CommandError` for an unknown or unavailable command, a missing or
  /// invalid argument, or a declined confirmation; rethrows what the command throws.
  @discardableResult
  public func run(
    _ id: CommandID, arguments: CommandArguments = [:], source: CommandSource = .program
  ) async throws -> CommandOutcome {
    guard let command = registry[id] else { throw CommandError.unknown(id) }
    let base = context(source: source)
    guard command.isAvailable(base) else { throw CommandError.unavailable(id) }

    var validated = CommandArguments()
    for parameter in command.params {
      guard let value = arguments[parameter.name] else {
        if parameter.isOptional { continue }
        throw CommandError.missingArgument(id, parameter: parameter.name)
      }
      guard let checked = parameter.validate(value, in: base) else {
        throw CommandError.invalidArgument(id, parameter: parameter.name)
      }
      validated[parameter.name] = checked
    }
    let context = base.with(arguments: validated)

    if command.risk == .outward {
      let approved: Bool
      if let confirmer {
        approved = await confirmer.confirm(command, in: context)
      } else {
        approved = [.key, .palette, .program].contains(source)
      }
      guard approved else {
        log.info("command \(id) declined (\(source.rawValue))")
        throw CommandError.declined(id)
      }
    }

    // Argument names only: values may be user content.
    let names = validated.values.keys.sorted().joined(separator: ",")
    log.info("command \(id) (\(source.rawValue))" + (names.isEmpty ? "" : " [\(names)]"))
    noteRecent(id)
    try await command.perform(context)
    let outcome = context.outcome
    if let undo = outcome.undo { undoSink?.register(undo, for: command) }
    return outcome
  }

  /// The first target whose command is available now (several commands may share a key).
  public func firstAvailable(_ targets: [Keymap.Target], source: CommandSource = .key)
    -> Keymap.Target?
  {
    let context = context(source: source)
    return targets.first { registry[$0.command]?.isAvailable(context) == true }
  }

  private func noteRecent(_ id: CommandID) {
    recent.removeAll { $0 == id }
    recent.insert(id, at: 0)
    if recent.count > 50 { recent.removeLast() }
  }
}
