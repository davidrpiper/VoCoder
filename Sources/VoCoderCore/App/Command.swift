// The command registry (DESIGN §2.1). P1-04 has the minimum a module needs to contribute a
// command; P1-05 adds key bindings, voice phrases, parameters, risk tier, availability and the
// spoken result, and the dispatcher, keymap and palette on top.

/// A user-facing action. Keys, palette, voice and the brain all dispatch through these.
public struct Command: Identifiable, Sendable {
  public let id: CommandID
  public let title: String
  /// Palette / help grouping ("Tabs", "Agent", "Demo").
  public let category: String
  public let perform: @MainActor @Sendable (CommandContext) async throws -> Void

  public init(
    id: CommandID, title: String, category: String,
    perform: @escaping @MainActor @Sendable (CommandContext) async throws -> Void
  ) {
    self.id = id
    self.title = title
    self.category = category
    self.perform = perform
  }
}

/// What a command runs against.
@MainActor
public struct CommandContext {
  public let state: AppState

  public init(state: AppState) { self.state = state }
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

  /// Adds `command`; returns false (and adds nothing) when its id is taken.
  @discardableResult
  public mutating func register(_ command: Command) -> Bool {
    guard indices[command.id] == nil else { return false }
    append(command)
    return true
  }

  private mutating func append(_ command: Command) {
    indices[command.id] = all.count
    all.append(command)
  }
}

public enum CommandError: Error, Equatable {
  case unknown(CommandID)
}
