import Testing
import VoCoderCore

// MARK: Key chords and sequences

@Suite struct KeyChordTests {
  @Test func bridgeAndConfigSpellingsAgree() {
    let cases: [(String, String)] = [
      ("Ctrl-Space", "Ctrl-Space"), ("ctrl+space", "Ctrl-Space"), ("C-space", "Ctrl-Space"),
      ("ctrl+p", "Ctrl-p"), ("Ctrl-P", "Ctrl-p"), ("ctrl+shift+p", "Ctrl-Shift-p"),
      ("shift+tab", "Shift-Tab"), ("Shift-Tab", "Shift-Tab"), ("alt+1", "Alt-1"),
      ("option+1", "Alt-1"), ("ctrl+alt+x", "Ctrl-Alt-x"), ("j", "j"), ("G", "G"),
      ("shift+g", "G"), ("?", "?"), ("-", "-"), ("ctrl+-", "Ctrl--"), ("alt++", "Alt-+"),
      ("esc", "Esc"), ("Escape", "Esc"), ("enter", "Enter"), ("return", "Enter"),
      ("pgdn", "PageDown"), ("PageUp", "PageUp"), ("down", "ArrowDown"),
      ("ArrowLeft", "ArrowLeft"), ("f5", "F5"), ("F12", "F12"), ("space", "Space"),
    ]
    for (text, name) in cases {
      #expect(KeyChord(text)?.name == name, "\(text)")
    }
  }

  @Test func rejectsNonKeys() {
    for text in ["", "ctrl+", "hyper+x", "f13", "foo", "ctrl+foo", "a b"] {
      #expect(KeyChord(text) == nil, "\(text)")
    }
  }

  @Test func displayNames() {
    #expect(KeyChord("Ctrl-p")?.displayName == "^P")
    #expect(KeyChord("Ctrl-Space")?.displayName == "^Space")
    #expect(KeyChord("ArrowDown")?.displayName == "↓")
    #expect(KeyChord("Shift-ArrowUp")?.displayName == "Shift-↑")
    #expect(KeyChord("Alt-1")?.displayName == "Alt-1")
  }

  @Test func sequencesParseWithTheLeader() {
    let sequence = KeySequence(parsing: "<leader> t n")
    #expect(sequence?.steps == [.leader, .chord(KeyChord("t")!), .chord(KeyChord("n")!)])
    #expect(
      sequence?.chords(leader: KeyChord("Ctrl-a")!).map(\.name) == ["Ctrl-a", "t", "n"])
    #expect(KeySequence(parsing: "leader ctrl+p")?.steps.count == 2)
    #expect(KeySequence(parsing: "") == nil)
    #expect(KeySequence(parsing: "<leader> nope") == nil)
    let literal: KeySequence = "<leader> nope"
    #expect(!literal.isValid)
    #expect(literal.source == "<leader> nope")
  }
}

// MARK: Keymap

@MainActor
private func command(
  _ id: CommandID, keys: [KeyBinding] = [], category: String = "Test", title: String? = nil,
  phrases: [String] = [], params: [CommandParameter] = [], risk: RiskTier = .readOnly,
  available: @escaping Command.Availability = { _ in true },
  perform: @escaping Command.Perform
) -> Command {
  Command(
    id: id, title: title ?? id.rawValue, category: category, keys: keys, voicePhrases: phrases,
    params: params, risk: risk, isAvailable: available, perform: perform)
}

@MainActor
private func command(
  _ id: CommandID, keys: [KeyBinding] = [], category: String = "Test", title: String? = nil,
  phrases: [String] = [], params: [CommandParameter] = [], risk: RiskTier = .readOnly
) -> Command {
  command(
    id, keys: keys, category: category, title: title, phrases: phrases, params: params,
    risk: risk, perform: { _ in })
}

private func chords(_ names: String...) -> [KeyChord] { names.map { KeyChord($0)! } }

@MainActor
@Suite struct KeymapTests {
  let commands = [
    command("tab.next", keys: ["<leader> t n"], category: "Tabs"),
    command("tab.previous", keys: ["<leader> t p"], category: "Tabs"),
    command("palette.open", keys: ["Ctrl-p", "<leader> p"]),
    command("list.down", keys: ["j", "ArrowDown"]),
    command(
      "tab.goto",
      keys: (1...3).map { KeyBinding(keys: "<leader> \($0)", arguments: ["tab": .text("\($0)")]) }
    ),
  ]

  @Test func singleKeysAndSequencesResolve() {
    let keymap = Keymap(commands: commands)
    #expect(keymap.issues.isEmpty)
    #expect(keymap.lookup(chords("j")) == .targets([.init(command: "list.down", arguments: [:])]))
    #expect(keymap.lookup(chords("Ctrl-Space")) == .prefix)
    #expect(keymap.lookup(chords("Ctrl-Space", "t")) == .prefix)
    #expect(
      keymap.lookup(chords("Ctrl-Space", "t", "n"))
        == .targets([.init(command: "tab.next", arguments: [:])]))
    #expect(
      keymap.lookup(chords("Ctrl-Space", "2"))
        == .targets([.init(command: "tab.goto", arguments: ["tab": "2"])]))
    #expect(keymap.lookup(chords("x")) == .none)
    #expect(keymap.lookup(chords("Ctrl-Space", "x")) == .none)
  }

  @Test func resolverWalksSequences() {
    let keymap = Keymap(commands: commands)
    var resolver = KeyResolver()
    #expect(resolver.feed(KeyChord("Ctrl-Space")!, in: keymap) == .pending(chords("Ctrl-Space")))
    #expect(resolver.feed(KeyChord("t")!, in: keymap) == .pending(chords("Ctrl-Space", "t")))
    #expect(
      resolver.feed(KeyChord("p")!, in: keymap)
        == .matched(
          [.init(command: "tab.previous", arguments: [:])],
          sequence: chords("Ctrl-Space", "t", "p")))
    #expect(resolver.pending.isEmpty)
    // Esc or a dead end abandons the prefix and is swallowed.
    _ = resolver.feed(KeyChord("Ctrl-Space")!, in: keymap)
    #expect(resolver.feed(.escape, in: keymap) == .cancelled(chords("Ctrl-Space", "Esc")))
    _ = resolver.feed(KeyChord("Ctrl-Space")!, in: keymap)
    #expect(resolver.feed(KeyChord("z")!, in: keymap) == .cancelled(chords("Ctrl-Space", "z")))
    #expect(resolver.feed(KeyChord("z")!, in: keymap) == .unbound(KeyChord("z")!))
  }

  @Test func continuationsListTheNextKeys() {
    let keymap = Keymap(commands: commands)
    let next = keymap.continuations(after: chords("Ctrl-Space"))
    #expect(next.map(\.chord.name) == ["t", "p", "1", "2", "3"])
    #expect(next[0].isGroup)
    #expect(next[0].group == ["tab.next", "tab.previous"])
    #expect(next[1].targets.map(\.command) == ["palette.open"])
    let tabs = keymap.continuations(after: chords("Ctrl-Space", "t"))
    #expect(tabs.map(\.chord.name) == ["n", "p"])
  }

  @Test func overridesReplaceUnbindAndMoveTheLeader() {
    let overrides = KeyBindingOverrides(
      leader: KeyChord("Ctrl-a"),
      bindings: ["list.down": ["n"], "palette.open": [], "nope": ["x"]])
    let keymap = Keymap(commands: commands, overrides: overrides)
    #expect(keymap.lookup(chords("n")) == .targets([.init(command: "list.down", arguments: [:])]))
    #expect(keymap.lookup(chords("j")) == .none)
    #expect(keymap.lookup(chords("Ctrl-p")) == .none)
    #expect(keymap.lookup(chords("Ctrl-Space")) == .none)
    #expect(keymap.lookup(chords("Ctrl-a", "t", "n")) != .none)
    #expect(keymap.issues == ["keys for unknown command 'nope'"])
    #expect(keymap.sequences(for: "palette.open").isEmpty)
  }

  @Test func overridesParseFromConfigValues() {
    let (overrides, errors) = KeyBindingOverrides.parse(
      leader: "ctrl+b", bindings: ["tab.next": ["<leader> n", "ctrl+tab+x"], "list.down": []])
    #expect(overrides.leader == KeyChord("Ctrl-b"))
    #expect(overrides.bindings["tab.next"] == [KeySequence(parsing: "<leader> n")!])
    #expect(overrides.bindings["list.down"] == [])
    #expect(errors.count == 1)
    #expect(errors.first?.contains("ctrl+tab+x") == true)
    let (_, leaderErrors) = KeyBindingOverrides.parse(leader: "hyper", bindings: [:])
    #expect(leaderErrors.count == 1)
  }

  @Test func conflictsAreReported() {
    let keymap = Keymap(commands: [
      command("a", keys: ["g"]),
      command("b", keys: ["g g"]),
      command("c", keys: ["<leader>"]),
      command("d", keys: ["<leader> x", "<leader> what"]),
      command("e", keys: ["j"]),
      command("f", keys: ["j"]),
    ])
    #expect(
      keymap.issues == [
        "d: '<leader> what' is not a key sequence",
        "a: 'g' is shadowed by longer sequences",
        "c: '<leader>' is shadowed by longer sequences",
      ])
    #expect(keymap.lookup(chords("g")) == .prefix)
    // The same keys on several commands: all are candidates, in registration order.
    #expect(
      keymap.lookup(chords("j"))
        == .targets([.init(command: "e", arguments: [:]), .init(command: "f", arguments: [:])]))
  }

  @Test func displayUsesShortNames() {
    let keymap = Keymap(commands: commands)
    #expect(keymap.display(chords("Ctrl-Space", "t", "n")) == "^Space t n")
    #expect(keymap.sequences(for: "palette.open").map(keymap.display) == ["^P", "^Space p"])
  }
}

// MARK: Fuzzy ranking

@MainActor
@Suite struct FuzzyRankingTests {
  @Test func matchesSubsequencesCaseInsensitively() {
    #expect(FuzzyMatcher.score("ntab", in: "Next tab") != nil)
    #expect(FuzzyMatcher.score("NT", in: "next tab") != nil)
    #expect(FuzzyMatcher.score("tn", in: "Next tab") == nil)
    #expect(FuzzyMatcher.score("", in: "anything") == 0)
    #expect(FuzzyMatcher.score("longer than", in: "short") == nil)
  }

  @Test func prefersWordStartsPrefixesAndRuns() {
    func better(_ query: String, _ a: String, than b: String) {
      let sa = FuzzyMatcher.score(query, in: a) ?? .min
      let sb = FuzzyMatcher.score(query, in: b) ?? .min
      #expect(sa > sb, "\(query): \(a) (\(sa)) vs \(b) (\(sb))")
    }
    better("tab", "Tab next", than: "Go to stable")
    better("nt", "Next tab", than: "Mention")
    better("pal", "Command palette", than: "Help all")
    better("cp", "Command palette", than: "Scope")
    better("gt", "goToTab", than: "regatta")
    better("help", "Help", than: "Show help overlay")
  }

  let commands = [
    command("tab.next", category: "Tabs", title: "Next tab", phrases: ["next tab"]),
    command("tab.previous", category: "Tabs", title: "Previous tab"),
    command("palette.open", category: "App", title: "Command palette"),
    command("help.toggle", category: "App", title: "Help"),
    command("demo.ping", category: "Demo", title: "Ping"),
  ]

  @Test func ranksTitlesFirstThenIdsAndCategories() {
    #expect(
      CommandSearch.rank("tab", commands).map(\.id).prefix(2) == ["tab.next", "tab.previous"])
    #expect(CommandSearch.rank("palette", commands).first?.id == "palette.open")
    #expect(CommandSearch.rank("demo", commands).map(\.id) == ["demo.ping"])
    #expect(CommandSearch.rank("xyz", commands).isEmpty)
  }

  @Test func tiesGoToRecentThenRegistrationOrder() {
    #expect(CommandSearch.rank("", commands).map(\.id) == commands.map(\.id))
    let recent: [CommandID] = ["demo.ping", "help.toggle"]
    #expect(
      CommandSearch.rank("", commands, recent: recent).map(\.id).prefix(3)
        == ["demo.ping", "help.toggle", "tab.next"])
  }
}

// MARK: Dispatcher

@MainActor
private final class RecordingConfirmer: CommandConfirmer {
  var answer: Bool
  var asked: [CommandID] = []
  init(answer: Bool) { self.answer = answer }
  func confirm(_ command: Command, in context: CommandContext) async -> Bool {
    asked.append(command.id)
    return answer
  }
}

@MainActor
private final class RecordingUndoSink: UndoSink {
  var titles: [String] = []
  func register(_ undo: UndoAction, for command: Command) { titles.append(undo.title) }
}

@MainActor
final class EntryLog {
  var entries: [String] = []
}

@MainActor
@Suite struct DispatcherTests {
  let state = AppState()
  let log = EntryLog()
  let dispatcher: CommandDispatcher

  init() {
    let log = log
    dispatcher = CommandDispatcher(state: state)
    dispatcher.register([
      command("echo", params: [CommandParameter("text", title: "Text")]) { context in
        log.entries.append("echo \(context.arguments.text("text") ?? "")")
        context.say("echoed")
      },
      command(
        "count", params: [CommandParameter("n", title: "N", kind: .integer(1...3))]
      ) { context in
        log.entries.append("count \(context.arguments.integer("n") ?? 0)")
      },
      command(
        "pick",
        params: [
          CommandParameter(
            "color", title: "Colour",
            kind: .choice { _ in [.init(value: "red", title: "Red")] }),
          CommandParameter("note", title: "Note", isOptional: true),
        ]
      ) { context in
        log.entries.append("pick \(context.arguments.text("color") ?? "")")
      },
      command("focused", available: { $0.focus.contains("list") }) { context in
        log.entries.append("focused \(context.focus.focused ?? "-") \(context.source)")
      },
      command("push", risk: .outward) { _ in log.entries.append("push") },
      command("archive", risk: .reversible) { context in
        log.entries.append("archive")
        context.offerUndo(UndoAction(title: "Unarchive") { log.entries.append("unarchive") })
      },
    ])
  }

  @Test func runsWithArgumentsAndReturnsTheOutcome() async throws {
    let outcome = try await dispatcher.run("echo", arguments: ["text": "hi"])
    #expect(outcome.spoken == "echoed")
    #expect(log.entries == ["echo hi"])
    #expect(dispatcher.recent == ["echo"])
  }

  @Test func validatesArguments() async throws {
    await #expect(throws: CommandError.unknown("nope")) { try await dispatcher.run("nope") }
    await #expect(throws: CommandError.missingArgument("echo", parameter: "text")) {
      try await dispatcher.run("echo")
    }
    await #expect(throws: CommandError.invalidArgument("count", parameter: "n")) {
      try await dispatcher.run("count", arguments: ["n": 7])
    }
    await #expect(throws: CommandError.invalidArgument("count", parameter: "n")) {
      try await dispatcher.run("count", arguments: ["n": "two"])
    }
    await #expect(throws: CommandError.invalidArgument("pick", parameter: "color")) {
      try await dispatcher.run("pick", arguments: ["color": "blue"])
    }
    try await dispatcher.run("count", arguments: ["n": "2"])  // text converts
    try await dispatcher.run("pick", arguments: ["color": "red"])  // optional note omitted
    #expect(log.entries == ["count 2", "pick red"])
    #expect(dispatcher.missingParameters(of: "pick").map(\.name) == ["color"])
    #expect(dispatcher.missingParameters(of: "pick", given: ["color": "red"]).isEmpty)
  }

  @Test func availabilitySeesTheFocus() async throws {
    #expect(!dispatcher.isAvailable("focused"))
    #expect(!dispatcher.available().map(\.id).contains("focused"))
    await #expect(throws: CommandError.unavailable("focused")) {
      try await dispatcher.run("focused")
    }
    dispatcher.focusProvider = { FocusSnapshot(focused: "list", path: ["pane", "list"]) }
    #expect(dispatcher.isAvailable("focused"))
    try await dispatcher.run("focused", source: .key)
    #expect(log.entries == ["focused list key"])
    let targets: [Keymap.Target] = [
      .init(command: "missing", arguments: [:]), .init(command: "focused", arguments: [:]),
    ]
    #expect(dispatcher.firstAvailable(targets)?.command == "focused")
  }

  @Test func outwardCommandsNeedConfirmationOutsideExplicitChoice() async throws {
    try await dispatcher.run("push", source: .key)
    try await dispatcher.run("push", source: .palette)
    await #expect(throws: CommandError.declined("push")) {
      try await dispatcher.run("push", source: .voice)
    }
    let confirmer = RecordingConfirmer(answer: false)
    dispatcher.confirmer = confirmer
    await #expect(throws: CommandError.declined("push")) {
      try await dispatcher.run("push", source: .key)
    }
    confirmer.answer = true
    try await dispatcher.run("push", source: .voice)
    try await dispatcher.run("echo", arguments: ["text": "x"], source: .voice)  // not asked
    #expect(confirmer.asked == ["push", "push"])
    #expect(log.entries == ["push", "push", "push", "echo x"])
  }

  @Test func undoActionsGoToTheSink() async throws {
    let sink = RecordingUndoSink()
    dispatcher.undoSink = sink
    let outcome = try await dispatcher.run("archive")
    #expect(sink.titles == ["Unarchive"])
    try await outcome.undo?.perform()
    #expect(log.entries == ["archive", "unarchive"])
  }

  @Test func builtInsGoFirstAndReplaceModuleCommands() {
    let replaced = dispatcher.registerBuiltIns([command("echo"), command("builtin")])
    #expect(replaced.map(\.id) == ["echo"])
    #expect(dispatcher.registry.all.map(\.id).prefix(3) == ["echo", "builtin", "count"])
    #expect(dispatcher["echo"]?.params.isEmpty == true)
    #expect(dispatcher.register([command("count")]) == ["count"])
  }
}

// MARK: Tab commands

@MainActor
@Suite struct TabCommandTests {
  @Test func navigateTabs() async throws {
    let state = AppState()
    let dispatcher = CommandDispatcher(state: state, registry: CommandRegistry(TabCommands.all))
    #expect(!dispatcher.isAvailable(TabCommands.next))
    for id in ["a", "b", "c"] {
      state.open(FakeTabForCommands(id: TabID(id)))
    }
    var outcome = try await dispatcher.run(TabCommands.next)
    #expect(state.selectedTabID == "b")
    #expect(outcome.spoken == "b")
    try await dispatcher.run(TabCommands.previous)
    try await dispatcher.run(TabCommands.previous)
    #expect(state.selectedTabID == "c")
    outcome = try await dispatcher.run(TabCommands.goto, arguments: ["tab": "1"])
    #expect(state.selectedTabID == "a")
    await #expect(throws: CommandError.invalidArgument(TabCommands.goto, parameter: "tab")) {
      try await dispatcher.run(TabCommands.goto, arguments: ["tab": "9"])
    }
    var titles: [String] = []
    if let parameter = dispatcher[TabCommands.goto]?.params.first,
      case .choice(let choices) = parameter.kind
    {
      titles = choices(dispatcher.context()).map(\.title)
    }
    #expect(titles == ["1 a", "2 b", "3 c"])
    let keymap = Keymap(commands: TabCommands.all)
    #expect(keymap.issues.isEmpty)
    #expect(
      keymap.lookup(chords("Alt-3"))
        == .targets([.init(command: TabCommands.goto, arguments: ["tab": "3"])]))
  }
}

@MainActor
private final class FakeTabForCommands: Tab {
  let id: TabID
  var title: String { id.rawValue }
  let aliases: [String] = []
  let badge = TabBadge.none
  init(id: TabID) { self.id = id }
}
