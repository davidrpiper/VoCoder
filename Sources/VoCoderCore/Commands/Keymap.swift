// Key sequences → commands (DESIGN §3.3). Built from the commands' default bindings plus the
// user's overrides; resolved one chord at a time by `KeyResolver`, which also drives the
// which-key popup while a prefix (the leader, usually) is pending.

/// The user's key changes (config `[keys]`, parsed in P1-06).
public struct KeyBindingOverrides: Sendable, Equatable {
  /// Replaces `Ctrl-Space`.
  public var leader: KeyChord?
  /// Replaces a command's default bindings; an empty list unbinds it.
  public var bindings: [CommandID: [KeySequence]]

  public init(leader: KeyChord? = nil, bindings: [CommandID: [KeySequence]] = [:]) {
    self.leader = leader
    self.bindings = bindings
  }

  /// From config values (`leader = "ctrl+space"`, `"tab.next" = ["<leader> n"]`). Parts that
  /// don't parse are left out and described in `errors`.
  public static func parse(leader: String?, bindings: [String: [String]])
    -> (overrides: KeyBindingOverrides, errors: [String])
  {
    var overrides = KeyBindingOverrides()
    var errors: [String] = []
    if let leader {
      if let chord = KeyChord(leader) {
        overrides.leader = chord
      } else {
        errors.append("leader: '\(leader)' is not a key (try \"ctrl+space\")")
      }
    }
    for (command, texts) in bindings.sorted(by: { $0.key < $1.key }) {
      var sequences: [KeySequence] = []
      for text in texts {
        if let sequence = KeySequence(parsing: text) {
          sequences.append(sequence)
        } else {
          errors.append(
            "\(command): '\(text)' is not a key sequence (e.g. \"ctrl+p\", \"<leader> t n\")")
        }
      }
      overrides.bindings[CommandID(command)] = sequences
    }
    return (overrides, errors)
  }
}

public struct Keymap: Sendable {
  /// What a complete sequence runs.
  public struct Target: Hashable, Sendable {
    public let command: CommandID
    public let arguments: CommandArguments

    public init(command: CommandID, arguments: CommandArguments = [:]) {
      self.command = command
      self.arguments = arguments
    }
  }

  public enum Lookup: Equatable, Sendable {
    case none
    /// More keys can follow.
    case prefix
    /// Candidates in registration order; the first available one runs.
    case targets([Target])
  }

  /// One key that can follow a pending prefix (a which-key row).
  public struct Continuation: Sendable, Equatable {
    public let chord: KeyChord
    /// Set when pressing `chord` completes a sequence.
    public let targets: [Target]
    /// Commands reachable through further keys when `chord` is itself a prefix.
    public let group: [CommandID]

    public var isGroup: Bool { targets.isEmpty }
  }

  public let leader: KeyChord
  /// Bindings that were dropped, and why (shown by `vocoder doctor`, logged).
  public private(set) var issues: [String] = []

  private var entries: [(chords: [KeyChord], target: Target)] = []
  private var targetsBySequence: [[KeyChord]: [Target]] = [:]
  private var prefixes: Set<[KeyChord]> = []

  public init(commands: [Command], overrides: KeyBindingOverrides = KeyBindingOverrides()) {
    leader = overrides.leader ?? .leaderDefault
    let known = Set(commands.map(\.id))
    for id in overrides.bindings.keys.sorted() where !known.contains(id) {
      issues.append("keys for unknown command '\(id)'")
    }

    var candidates: [(chords: [KeyChord], target: Target, source: String)] = []
    for command in commands {
      let bindings = overrides.bindings[command.id]?.map { KeyBinding($0) } ?? command.keys
      for binding in bindings {
        guard binding.sequence.isValid else {
          issues.append("\(command.id): '\(binding.sequence)' is not a key sequence")
          continue
        }
        let target = Target(command: command.id, arguments: binding.arguments)
        let chords = binding.sequence.chords(leader: leader)
        if candidates.contains(where: { $0.chords == chords && $0.target == target }) { continue }
        candidates.append((chords, target, binding.sequence.source))
      }
    }

    for candidate in candidates {
      for length in 1..<candidate.chords.count {
        prefixes.insert(Array(candidate.chords[..<length]))
      }
    }
    for candidate in candidates {
      // A sequence that starts longer ones would never be reached (no timeouts).
      if prefixes.contains(candidate.chords) {
        issues.append(
          "\(candidate.target.command): '\(candidate.source)' is shadowed by longer sequences")
        continue
      }
      entries.append((candidate.chords, candidate.target))
      targetsBySequence[candidate.chords, default: []].append(candidate.target)
    }
  }

  public func lookup(_ sequence: [KeyChord]) -> Lookup {
    if let targets = targetsBySequence[sequence] { return .targets(targets) }
    return prefixes.contains(sequence) ? .prefix : .none
  }

  /// The keys that can follow `prefix`, in registration order of their first command.
  public func continuations(after prefix: [KeyChord]) -> [Continuation] {
    var order: [KeyChord] = []
    var targets: [KeyChord: [Target]] = [:]
    var groups: [KeyChord: [CommandID]] = [:]
    for entry in entries where entry.chords.count > prefix.count {
      guard Array(entry.chords[..<prefix.count]) == prefix else { continue }
      let next = entry.chords[prefix.count]
      if targets[next] == nil, groups[next] == nil { order.append(next) }
      if entry.chords.count == prefix.count + 1 {
        targets[next, default: []].append(entry.target)
      } else if groups[next]?.contains(entry.target.command) != true {
        groups[next, default: []].append(entry.target.command)
      }
    }
    return order.map {
      Continuation(chord: $0, targets: targets[$0] ?? [], group: groups[$0] ?? [])
    }
  }

  /// The sequences that run `command` (any arguments), in binding order.
  public func sequences(for command: CommandID) -> [[KeyChord]] {
    entries.filter { $0.target.command == command }.map(\.chords)
  }

  /// "^Space t n".
  public func display(_ sequence: [KeyChord]) -> String {
    sequence.map(\.displayName).joined(separator: " ")
  }
}

/// Feeds chords through a keymap one at a time.
public struct KeyResolver: Sendable {
  public enum Result: Equatable, Sendable {
    /// Waiting for more keys (show the which-key popup for this prefix).
    case pending([KeyChord])
    case matched([Keymap.Target], sequence: [KeyChord])
    /// A pending prefix was abandoned (Esc, or a key that continues nothing). The key is
    /// swallowed.
    case cancelled([KeyChord])
    /// Nothing pending and the key is bound to nothing.
    case unbound(KeyChord)
  }

  public private(set) var pending: [KeyChord] = []

  public init() {}

  public mutating func feed(_ chord: KeyChord, in keymap: Keymap) -> Result {
    let sequence = pending + [chord]
    switch keymap.lookup(sequence) {
    case .targets(let targets):
      pending = []
      return .matched(targets, sequence: sequence)
    case .prefix:
      pending = sequence
      return .pending(sequence)
    case .none:
      guard !pending.isEmpty else { return .unbound(chord) }
      pending = []
      return .cancelled(sequence)
    }
  }

  public mutating func reset() { pending = [] }
}
