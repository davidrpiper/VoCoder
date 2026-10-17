// Key names as the UI bridge's decoder produces them ("j", "G", "Ctrl-p", "Ctrl-Space",
// "Shift-Tab", "Alt-1", "ArrowDown", "F5"). Bindings may also be written config-style
// ("ctrl+space", "shift+tab", "alt+1"); both parse to the same chord.
import Foundation

/// One key press with its modifiers, named exactly as the bridge reports it.
public struct KeyChord: Hashable, Sendable, CustomStringConvertible, Comparable {
  /// The bridge's name for the key.
  public let name: String

  /// Parses `text` ("Ctrl-Space", "ctrl+space", "G", "shift+g", "PgDn"); nil if it isn't a key.
  public init?(_ text: String) {
    guard let name = Self.canonicalName(text) else { return nil }
    self.name = name
  }

  public static let leaderDefault = KeyChord("Ctrl-Space")!
  public static let escape = KeyChord("Esc")!

  public var description: String { name }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.name < rhs.name }

  /// Short form for popups and hints: "^P", "^Space", "↓", "Alt-1".
  public var displayName: String {
    var rest = name
    var prefix = ""
    if rest.hasPrefix("Ctrl-"), rest.count > 5 {
      rest.removeFirst(5)
      prefix = "^"
      if rest.count == 1 { rest = rest.uppercased() }
    }
    let arrows = ["ArrowUp": "↑", "ArrowDown": "↓", "ArrowLeft": "←", "ArrowRight": "→"]
    for (arrow, glyph) in arrows where rest.hasSuffix(arrow) {
      rest = String(rest.dropLast(arrow.count)) + glyph
    }
    return prefix + rest
  }

  /// A modifier prefix ("Ctrl-", "Alt-") as `displayName` writes it ("^", "Alt-").
  public static func displayModifiers(_ prefix: String) -> String {
    prefix.hasPrefix("Ctrl-") ? "^" + prefix.dropFirst(5) : prefix
  }

  // MARK: Parsing

  private static let namedKeys: [String: String] = [
    "space": "Space", "spc": "Space", "tab": "Tab", "enter": "Enter", "return": "Enter",
    "ret": "Enter", "esc": "Esc", "escape": "Esc", "backspace": "Backspace", "bs": "Backspace",
    "delete": "Delete", "del": "Delete", "insert": "Insert", "ins": "Insert", "home": "Home",
    "end": "End", "pageup": "PageUp", "pgup": "PageUp", "pagedown": "PageDown",
    "pgdn": "PageDown", "up": "ArrowUp", "arrowup": "ArrowUp", "down": "ArrowDown",
    "arrowdown": "ArrowDown", "left": "ArrowLeft", "arrowleft": "ArrowLeft",
    "right": "ArrowRight", "arrowright": "ArrowRight",
  ]

  private static func canonicalName(_ text: String) -> String? {
    let text = text.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty, !text.contains(" ") else { return nil }
    var tokens: [String]
    if text.count == 1 {
      tokens = [text]
    } else if let last = text.last, "+-".contains(last),
      text.dropLast().last.map({ "+-".contains($0) }) == true
    {
      // "ctrl++", "Ctrl--": the key is the separator character itself.
      tokens = splitModifiers(String(text.dropLast(2))) + [String(last)]
    } else {
      tokens = splitModifiers(text)
    }
    guard let base = tokens.popLast(), !base.isEmpty else { return nil }

    var ctrl = false
    var alt = false
    var shift = false
    for token in tokens {
      switch token.lowercased() {
      case "ctrl", "control", "c": ctrl = true
      case "alt", "option", "opt", "meta", "m": alt = true
      case "shift", "s": shift = true
      default: return nil
      }
    }

    var key: String
    if base.count == 1 {
      key = base
      let isLetter = base.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isAlphabetic }
      if isLetter {
        if ctrl || alt {
          // Ctrl/Alt names use the lowercase letter, Shift stays explicit (as the decoder does).
          key = base.lowercased()
        } else if shift {
          key = base.uppercased()
          shift = false
        }
      } else if base == " " {
        key = "Space"
      }
    } else if let named = namedKeys[base.lowercased()] {
      key = named
    } else if base.lowercased().hasPrefix("f"), let number = Int(base.dropFirst()),
      (1...12).contains(number)
    {
      key = "F\(number)"
    } else {
      return nil
    }
    return (ctrl ? "Ctrl-" : "") + (alt ? "Alt-" : "") + (shift ? "Shift-" : "") + key
  }

  private static func splitModifiers(_ text: String) -> [String] {
    text.split(separator: /[+-]/, omittingEmptySubsequences: false).map(String.init)
  }
}

/// Keys pressed in turn ("<leader> t n"). `<leader>` stands for the configured leader chord.
public struct KeySequence: Hashable, Sendable, CustomStringConvertible,
  ExpressibleByStringLiteral
{
  public enum Step: Hashable, Sendable {
    case leader
    case chord(KeyChord)
  }

  public let steps: [Step]
  /// The text it was parsed from (for error messages).
  public let source: String

  public init(_ steps: [Step]) {
    self.steps = steps
    self.source = steps.map {
      switch $0 {
      case .leader: "<leader>"
      case .chord(let chord): chord.name
      }
    }.joined(separator: " ")
  }

  /// Parses space-separated keys; `<leader>` (or `leader`) is the leader. Nil if any part
  /// isn't a key.
  public init?(parsing text: String) {
    var steps: [Step] = []
    for part in text.split(separator: " ") {
      let part = String(part)
      if ["<leader>", "leader"].contains(part.lowercased()) {
        steps.append(.leader)
      } else if let chord = KeyChord(part) {
        steps.append(.chord(chord))
      } else {
        return nil
      }
    }
    guard !steps.isEmpty else { return nil }
    self.steps = steps
    self.source = text
  }

  /// A literal that doesn't parse has no steps; the keymap reports it as an issue.
  public init(stringLiteral value: String) {
    if let parsed = KeySequence(parsing: value) {
      self = parsed
    } else {
      steps = []
      source = value
    }
  }

  public var isValid: Bool { !steps.isEmpty }

  public var description: String { source }

  /// The chords to press, with `<leader>` replaced by `leader`.
  public func chords(leader: KeyChord) -> [KeyChord] {
    steps.map {
      switch $0 {
      case .leader: leader
      case .chord(let chord): chord
      }
    }
  }
}

/// A key sequence that runs a command, optionally with fixed arguments (`<leader> 3` →
/// `tab.goto` with `tab = 3`).
public struct KeyBinding: Hashable, Sendable, ExpressibleByStringLiteral {
  public let sequence: KeySequence
  public let arguments: CommandArguments

  public init(_ sequence: KeySequence, arguments: CommandArguments = [:]) {
    self.sequence = sequence
    self.arguments = arguments
  }

  /// `keys` as written in a literal ("<leader> 3"); invalid text is reported by the keymap.
  public init(keys: String, arguments: CommandArguments = [:]) {
    self.init(KeySequence(stringLiteral: keys), arguments: arguments)
  }

  public init(stringLiteral value: String) { self.init(keys: value) }
}
