// `vocoder doctor` checks of the terminal and the keyboard (DESIGN §5, ADR 0001): which
// terminal this is, whether Option sends Meta (Alt-digit tab keys), and whether macOS takes
// the leader (Ctrl-Space) for switching input sources. Inputs are read once into
// `TerminalEnvironment`, so the checks themselves are plain functions of values.
import Foundation
import VoCoderCore

public enum TerminalKind: Sendable, Equatable {
  case terminalApp, ghostty
  case other(String)
  case unknown

  public init(termProgram: String?) {
    switch termProgram {
    case "Apple_Terminal": self = .terminalApp
    case "ghostty": self = .ghostty
    case let name?: self = .other(name)
    case nil: self = .unknown
    }
  }
}

/// A macOS keyboard shortcut (`com.apple.symbolichotkeys`).
public struct SymbolicHotKey: Sendable, Equatable {
  /// 60/61: select the previous/next input source.
  public let id: Int
  public let enabled: Bool
  public let keyCode: Int
  public let modifiers: Int

  public init(id: Int, enabled: Bool, keyCode: Int, modifiers: Int) {
    self.id = id
    self.enabled = enabled
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  static let spaceKeyCode = 49
  static let controlMask = 0x40000

  var isControlSpace: Bool { keyCode == Self.spaceKeyCode && modifiers == Self.controlMask }
  /// Input-source shortcuts only act when more than one input source is enabled.
  var switchesInputSource: Bool { id == 60 || id == 61 }
}

/// What the terminal checks look at.
public struct TerminalEnvironment: Sendable {
  public var terminal: TerminalKind
  /// Terminal.app's default profile and its "Use Option as Meta key" setting.
  public var terminalAppProfile: (name: String, optionAsMeta: Bool)?
  /// Ghostty's config files, concatenated in load order.
  public var ghosttyConfig: String?
  public var hotKeys: [SymbolicHotKey]
  /// Enabled keyboard layouts and input methods (not the emoji palette and the like).
  public var keyboardInputSources: Int

  public init(
    terminal: TerminalKind, terminalAppProfile: (name: String, optionAsMeta: Bool)? = nil,
    ghosttyConfig: String? = nil, hotKeys: [SymbolicHotKey] = [], keyboardInputSources: Int = 1
  ) {
    self.terminal = terminal
    self.terminalAppProfile = terminalAppProfile
    self.ghosttyConfig = ghosttyConfig
    self.hotKeys = hotKeys
    self.keyboardInputSources = keyboardInputSources
  }

  /// Reads this Mac's settings.
  public static func current(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> TerminalEnvironment {
    var result = TerminalEnvironment(
      terminal: TerminalKind(termProgram: environment["TERM_PROGRAM"]))

    let terminalDefaults = UserDefaults(suiteName: "com.apple.Terminal")
    if let name = terminalDefaults?.string(forKey: "Default Window Settings"),
      let profiles = terminalDefaults?.dictionary(forKey: "Window Settings"),
      let profile = profiles[name] as? [String: Any]
    {
      result.terminalAppProfile = (name, (profile["useOptionAsMetaKey"] as? Bool) ?? false)
    }

    let configHome =
      environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
      ?? home.appending(path: ".config")
    let ghosttyFiles = [
      configHome.appending(path: "ghostty/config"),
      configHome.appending(path: "ghostty/config.ghostty"),
      home.appending(path: "Library/Application Support/com.mitchellh.ghostty/config"),
      home.appending(path: "Library/Application Support/com.mitchellh.ghostty/config.ghostty"),
    ]
    let texts = ghosttyFiles.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    result.ghosttyConfig = texts.isEmpty ? nil : texts.joined(separator: "\n")

    let hotKeys =
      UserDefaults(suiteName: "com.apple.symbolichotkeys")?
      .dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
    result.hotKeys = hotKeys.compactMap { key, value in
      guard let id = Int(key), let entry = value as? [String: Any],
        let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int],
        parameters.count == 3
      else { return nil }
      return SymbolicHotKey(
        id: id, enabled: (entry["enabled"] as? Bool) ?? false, keyCode: parameters[1],
        modifiers: parameters[2])
    }

    let sources =
      UserDefaults(suiteName: "com.apple.HIToolbox")?
      .array(forKey: "AppleEnabledInputSources") as? [[String: Any]] ?? []
    result.keyboardInputSources = sources.count {
      ["Keyboard Layout", "Input Mode"].contains($0["InputSourceKind"] as? String ?? "")
    }
    return result
  }
}

public enum TerminalDoctorChecks {
  public static func all(_ environment: TerminalEnvironment, leader: KeyChord) -> [any DoctorCheck]
  {
    [terminal(environment), optionAsMeta(environment), leaderShortcut(environment, leader: leader)]
  }

  public static func terminal(_ environment: TerminalEnvironment) -> any DoctorCheck {
    let kind = environment.terminal
    return ClosureDoctorCheck(id: "app.terminal", title: "Terminal") {
      let supported = "supported: Terminal.app (baseline), Ghostty (recommended)"
      switch kind {
      case .terminalApp: return .ok("Terminal.app")
      case .ghostty: return .ok("Ghostty")
      case .other("tmux"):
        return .warning(
          "running inside tmux; keys and colours depend on its settings",
          hint: "run vocoder directly in the terminal (\(supported))")
      case .other(let name):
        return .warning("\(name) isn't tested", hint: supported)
      case .unknown:
        return .warning("unknown terminal (no TERM_PROGRAM)", hint: supported)
      }
    }
  }

  /// Alt-1…9 switch tabs only when Option sends Meta/Alt (off by default).
  public static func optionAsMeta(_ environment: TerminalEnvironment) -> any DoctorCheck {
    let kind = environment.terminal
    let profile = environment.terminalAppProfile
    let ghostty = environment.ghosttyConfig.map(ghosttyOptionAsAlt)
    return ClosureDoctorCheck(id: "app.option-as-meta", title: "Option as Meta") {
      let effect = "Alt-1…9 won't switch tabs (Ctrl-Space 1…9 still does)"
      switch kind {
      case .terminalApp:
        guard let profile else {
          return .skipped("couldn't read Terminal.app's default profile")
        }
        if profile.optionAsMeta { return .ok("on in profile '\(profile.name)'") }
        return .warning(
          "off in profile '\(profile.name)': \(effect)",
          hint:
            "Terminal → Settings → Profiles → \(profile.name) → Keyboard → Use Option as Meta key")
      case .ghostty:
        if let value = ghostty ?? nil, value != "false" {
          return .ok("macos-option-as-alt = \(value)")
        }
        return .warning(
          "macos-option-as-alt is off: \(effect)",
          hint: "add `macos-option-as-alt = true` to Ghostty's config and reload it")
      case .other, .unknown:
        return .skipped("only checked for Terminal.app and Ghostty")
      }
    }
  }

  /// The last `macos-option-as-alt` value in a Ghostty config, if any.
  static func ghosttyOptionAsAlt(_ config: String) -> String? {
    var value: String?
    for line in config.split(separator: "\n") {
      let parts = line.split(separator: "=", maxSplits: 1).map {
        $0.trimmingCharacters(in: .whitespaces)
      }
      guard parts.count == 2, parts[0] == "macos-option-as-alt" else { continue }
      value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
    return value
  }

  /// macOS can take Ctrl-Space ("Select the previous input source") before the terminal sees it.
  public static func leaderShortcut(_ environment: TerminalEnvironment, leader: KeyChord)
    -> any DoctorCheck
  {
    let hotKeys = environment.hotKeys
    let sources = environment.keyboardInputSources
    return ClosureDoctorCheck(id: "app.leader", title: "Leader key") {
      guard leader == .leaderDefault else {
        return .ok("\(leader.displayName) (from [keys] leader)")
      }
      let taken = hotKeys.filter {
        $0.enabled && $0.isControlSpace && (!$0.switchesInputSource || sources > 1)
      }
      guard taken.isEmpty else {
        let what =
          taken.contains { $0.switchesInputSource }
          ? "macOS uses Ctrl-Space to switch input sources (\(sources) enabled)"
          : "a macOS keyboard shortcut uses Ctrl-Space"
        return .warning(
          "\(what), so the leader never reaches vocoder",
          hint:
            "System Settings → Keyboard → Keyboard Shortcuts → Input Sources: turn off or change"
            + " the shortcut, or set another [keys] leader")
      }
      return .ok("Ctrl-Space reaches the terminal")
    }
  }
}
