// The keyboard front-end of the command system (DESIGN §3.3, ADR 0007): every key the focused
// widget doesn't consume is resolved through the keymap (multi-key sequences, the leader with its
// which-key popup) to a command, run by the dispatcher. It also owns the palette and help
// overlays, which `CommandOverlays` draws.
import Foundation
import Observation
import VoCoderCore

@MainActor
@Observable
public final class KeyboardController {
  @ObservationIgnored public let host: UIHost
  @ObservationIgnored public let dispatcher: CommandDispatcher
  public private(set) var keymap: Keymap
  /// The keys of a pending sequence (the which-key popup shows while non-empty). Keys go to
  /// the controller, not a focused text field, while it is.
  public private(set) var pending: [KeyChord] = [] {
    didSet { host.suspendsWidgetFocus = !pending.isEmpty }
  }
  public let palette = PaletteModel()
  public private(set) var isHelpVisible = false
  public let helpScroll = ScrollState(pageSize: 10)
  /// Why the last command failed, until the next one runs (for a hint or toast).
  public private(set) var lastFailure: String?

  @ObservationIgnored private var resolver = KeyResolver()
  @ObservationIgnored private var overrides: KeyBindingOverrides
  /// The focus when an overlay opened: commands are offered and run for what was focused
  /// before, not for the overlay's own field.
  @ObservationIgnored private var underlyingFocus: FocusSnapshot?
  @ObservationIgnored private let log = Log(category: "keys")

  /// Registers the built-in UI commands with `dispatcher` (ahead of modules' commands), builds
  /// the keymap and takes over `host`'s keys. `quit` stops the app.
  public init(
    host: UIHost, dispatcher: CommandDispatcher,
    overrides: KeyBindingOverrides = KeyBindingOverrides(),
    quit: @escaping @MainActor @Sendable () -> Void
  ) {
    self.host = host
    self.dispatcher = dispatcher
    self.overrides = overrides
    keymap = Keymap(commands: [])
    let replaced = dispatcher.registerBuiltIns(NavigationCommands.make(for: self, quit: quit))
    for command in replaced {
      dispatcher.state.report(
        ModuleIssue(module: "core", message: "command id '\(command.id)' is built in"))
    }
    dispatcher.focusProvider = { [weak self, weak host] in
      self?.underlyingFocus ?? host?.focusSnapshot ?? .none
    }
    host.onKey = { [weak self] key in self?.handleKey(key) ?? false }
    rebuildKeymap()
  }

  /// Rebuilds the keymap from the registered commands (after registering more, or new
  /// overrides). Problems are logged and kept in `keymap.issues`.
  public func rebuildKeymap(overrides: KeyBindingOverrides? = nil) {
    if let overrides { self.overrides = overrides }
    keymap = Keymap(commands: dispatcher.registry.all, overrides: self.overrides)
    for issue in keymap.issues { log.error("keymap: \(issue)") }
    resolver.reset()
    pending = []
  }

  // MARK: Keys

  /// A key by its bridge name. Returns whether it was handled.
  @discardableResult
  public func handleKey(_ name: String) -> Bool {
    guard let chord = KeyChord(name) else {
      log.debug("unknown key name \(name)")
      return false
    }
    switch resolver.feed(chord, in: keymap) {
    case .pending(let sequence):
      pending = sequence
      return true
    case .cancelled:
      pending = []
      return true
    case .unbound:
      return false
    case .matched(let targets, _):
      pending = []
      guard let target = dispatcher.firstAvailable(targets, source: .key) else { return false }
      invoke(target.command, arguments: target.arguments, source: .key)
      return true
    }
  }

  /// Runs `id`, first asking in the palette for any required parameter `arguments` lacks.
  public func invoke(
    _ id: CommandID, arguments: CommandArguments = [:], source: CommandSource
  ) {
    guard let command = dispatcher[id] else {
      fail("unknown command \(id)")
      return
    }
    if !dispatcher.missingParameters(of: id, given: arguments).isEmpty {
      if !palette.isOpen { underlyingFocus = host.focusSnapshot }
      palette.prompt(for: command, arguments: arguments)
      host.setText("", for: PaletteModel.fieldID)
      palette.isOpen = true
      return
    }
    run(id, arguments: arguments, source: source)
  }

  /// Runs now, synchronously up to the command's first suspension, so key presses take
  /// effect before the next key is handled.
  private func run(_ id: CommandID, arguments: CommandArguments, source: CommandSource) {
    lastFailure = nil
    Task.immediate { [dispatcher, weak self] in
      do {
        try await dispatcher.run(id, arguments: arguments, source: source)
      } catch {
        self?.fail("\(error)")
      }
    }
  }

  private func fail(_ message: String) {
    log.info("command failed: \(message)")
    lastFailure = message
  }

  // MARK: Overlays

  public func openPalette() {
    isHelpVisible = false
    if !palette.isOpen { underlyingFocus = host.focusSnapshot }
    palette.reset()
    host.setText("", for: PaletteModel.fieldID)
    palette.isOpen = true
  }

  public func closePalette() {
    palette.isOpen = false
    palette.reset()
    underlyingFocus = nil
  }

  public func toggleHelp() {
    if isHelpVisible {
      isHelpVisible = false
      underlyingFocus = nil
    } else {
      if palette.isOpen { closePalette() }
      underlyingFocus = host.focusSnapshot
      isHelpVisible = true
    }
  }

  /// The palette's rows for its current stage and query.
  public var paletteItems: [PaletteItem] {
    switch palette.stage {
    case .commands:
      // Opening the palette from itself would do nothing.
      let offered = dispatcher.available(source: .palette).filter {
        $0.id != NavigationCommands.palette
      }
      var commands = CommandSearch.rank(palette.query, offered, recent: dispatcher.recent)
      if palette.query.isEmpty {
        commands = Self.navigationLast(commands, recent: dispatcher.recent)
      }
      return commands.map { command in
        PaletteItem(
          title: command.title, detail: command.category, keys: keyHint(for: command.id),
          value: command.id.rawValue)
      }
    case .parameter(let command, let index, _):
      guard case .choice(let choices) = command.params[index].kind else { return [] }
      let options = choices(dispatcher.context(source: .palette))
      let scored = options.enumerated().compactMap { offset, choice in
        FuzzyMatcher.score(palette.query, in: choice.title).map { (choice, $0, offset) }
      }
      return scored.sorted { ($0.1, -$0.2) > ($1.1, -$1.2) }.map {
        PaletteItem(title: $0.0.title, detail: "", keys: "", value: $0.0.value)
      }
    }
  }

  /// Available commands by category, in registration order (the help overlay).
  public var helpSections: [(category: String, entries: [PaletteItem])] {
    var order: [String] = []
    var sections: [String: [PaletteItem]] = [:]
    for command in Self.navigationLast(dispatcher.available(source: .key), recent: []) {
      if sections[command.category] == nil { order.append(command.category) }
      sections[command.category, default: []].append(
        PaletteItem(
          title: command.title, detail: command.category, keys: keyHint(for: command.id, limit: 3),
          value: command.id.rawValue))
    }
    return order.map { ($0, sections[$0]!) }
  }

  /// "^P" or "j, ↓" (the first `limit` bindings). Bindings that differ only in a final digit
  /// collapse into a range: "^Space 1…9".
  public func keyHint(for id: CommandID, limit: Int = 1) -> String {
    var hints: [String] = []
    var digits: [String: [Int]] = [:]
    for sequence in keymap.sequences(for: id) {
      let name = sequence.last!.name
      let modifiers = name.dropLast()
      if let digit = name.last?.wholeNumberValue, modifiers.isEmpty || modifiers.hasSuffix("-") {
        let lead = keymap.display(Array(sequence.dropLast()))
        let key = (lead.isEmpty ? "" : lead + " ") + KeyChord.displayModifiers(String(modifiers))
        if digits[key] == nil { hints.append(key) }
        digits[key, default: []].append(digit)
      } else {
        let text = keymap.display(sequence)
        if !hints.contains(text) { hints.append(text) }
      }
    }
    let texts = hints.map { hint -> String in
      guard let numbers = digits[hint], let low = numbers.min(), let high = numbers.max() else {
        return hint
      }
      return hint + (low == high ? "\(low)" : "\(low)…\(high)")
    }
    return texts.prefix(limit).joined(separator: ", ")
  }

  /// The generic navigation commands after the rest (unless recently used): an empty palette
  /// and the help start with what's specific to the app.
  private static func navigationLast(_ commands: [Command], recent: [CommandID]) -> [Command] {
    let isGeneric = { (command: Command) in
      command.category == NavigationCommands.category && !recent.contains(command.id)
    }
    return commands.filter { !isGeneric($0) } + commands.filter(isGeneric)
  }

  // MARK: Palette events

  func paletteQueryChanged(_ text: String) {
    palette.query = text
    palette.error = nil
    palette.list.selection = 0
  }

  func paletteSubmitted(_ text: String) {
    switch palette.stage {
    case .commands:
      let items = paletteItems
      guard let index = palette.list.selectedIndex(count: items.count) else { return }
      let id = CommandID(items[index].value)
      if dispatcher.missingParameters(of: id).isEmpty {
        closeAndRun(id, arguments: [:])
      } else {
        invoke(id, source: .palette)
      }
    case .parameter(let command, let index, var arguments):
      let parameter = command.params[index]
      let value: CommandValue
      switch parameter.kind {
      case .choice:
        let items = paletteItems
        guard let selected = palette.list.selectedIndex(count: items.count) else { return }
        value = .text(items[selected].value)
      case .integer:
        guard let number = CommandValue.text(text).integer else {
          palette.error = "Enter a number"
          return
        }
        value = .integer(number)
      case .text:
        value = .text(text)
      }
      guard parameter.validate(value, in: dispatcher.context(source: .palette)) != nil else {
        palette.error = "Not a valid \(parameter.title.lowercased())"
        return
      }
      arguments[parameter.name] = value
      if dispatcher.missingParameters(of: command.id, given: arguments).isEmpty {
        closeAndRun(command.id, arguments: arguments)
      } else {
        palette.prompt(for: command, arguments: arguments)
        host.setText("", for: PaletteModel.fieldID)
      }
    }
  }

  /// Arrow keys move the selection; Esc closes.
  func paletteAction(_ action: UIAction) -> Bool {
    let count = paletteItems.count
    switch action {
    case .cancel:
      closePalette()
      return true
    case .moveUp, .moveDown, .pageUp, .pageDown:
      return palette.list.perform(action, count: count)
    default:
      return false
    }
  }

  func helpAction(_ action: UIAction) -> Bool {
    guard action == .cancel else { return false }
    toggleHelp()
    return true
  }

  /// Closes the palette and renders, so focus is back where it was before the command runs.
  private func closeAndRun(_ id: CommandID, arguments: CommandArguments) {
    closePalette()
    host.render()
    run(id, arguments: arguments, source: .palette)
  }
}

/// A palette or help row.
public struct PaletteItem: Sendable, Equatable {
  public let title: String
  /// The category (commands) or nothing (choices).
  public let detail: String
  /// Key hint.
  public let keys: String
  /// Command id or choice value.
  public let value: String
}

/// The palette's state: open or not, the stage (choosing a command, or a parameter for one),
/// the query and the selection.
@MainActor
@Observable
public final class PaletteModel {
  public enum Stage {
    case commands
    /// Asking for `command.params[index]`; `arguments` collected so far.
    case parameter(command: Command, index: Int, arguments: CommandArguments)
  }

  public static let scopeID: FocusID = "palette"
  public static let fieldID: FocusID = "palette.query"

  public internal(set) var isOpen = false
  public internal(set) var stage = Stage.commands
  public internal(set) var query = ""
  public internal(set) var error: String?
  public let list = ListState(pageSize: 10)
  /// Rows shown at once.
  public var visibleRows = 10

  func reset() {
    stage = .commands
    query = ""
    error = nil
    list.selection = 0
  }

  /// Moves to the first required parameter `arguments` lacks.
  func prompt(for command: Command, arguments: CommandArguments) {
    let index = command.params.firstIndex { !$0.isOptional && arguments[$0.name] == nil } ?? 0
    stage = .parameter(command: command, index: index, arguments: arguments)
    query = ""
    error = nil
    list.selection = 0
  }

  /// "Commands", or "Go to tab › Tab".
  public var title: String {
    switch stage {
    case .commands: "Commands"
    case .parameter(let command, let index, _): "\(command.title) › \(command.params[index].title)"
    }
  }
}
