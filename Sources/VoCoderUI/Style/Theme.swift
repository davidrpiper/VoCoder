// Themes map semantic roles to colours (DESIGN §3.1). Views use roles; only themes pick values.
import Foundation
import VoCoderCore

/// A semantic colour role.
public enum ThemeRole: String, Sendable, CaseIterable {
  /// Body text. Unset in the built-in themes: the terminal's own foreground.
  case text
  /// Secondary text: hints, timestamps, placeholders.
  case muted
  /// Emphasis: titles, the active tab, links.
  case accent
  case success
  case warning
  case danger
  case info
  /// Borders of unfocused panels.
  case border
  /// Border of the focused panel.
  case focus
  /// Background of the selected row in the focused list.
  case selection
  /// Text on `selection`. Unset in the built-in themes: the terminal's own foreground.
  case selectionText
  /// Background of the selected row in an unfocused list.
  case inactiveSelection
  /// Background of code blocks and inline code.
  case codeBackground
}

/// Light or dark terminal background.
public enum Appearance: String, Sendable, CaseIterable {
  case dark
  case light

  /// The macOS appearance setting. Terminals usually follow it; config can override (P1-06).
  public static func system(defaults: UserDefaults = .standard) -> Appearance {
    defaults.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
  }
}

public struct Theme: Sendable, Equatable {
  public let name: String
  public let appearance: Appearance
  private let colors: [ThemeRole: Color]

  /// `colors` must be concrete (not `.role`); roles without a colour use the terminal default.
  public init(name: String, appearance: Appearance, colors: [ThemeRole: Color]) {
    precondition(
      !colors.values.contains { if case .role = $0 { true } else { false } },
      "theme colours must be concrete")
    self.name = name
    self.appearance = appearance
    self.colors = colors
  }

  public subscript(role: ThemeRole) -> Color? { colors[role] }

  /// The built-in theme for an appearance.
  public static func builtIn(_ appearance: Appearance) -> Theme {
    appearance == .dark ? dark : light
  }

  /// The built-in theme matching the macOS appearance (`auto`, the default).
  public static func automatic(defaults: UserDefaults = .standard) -> Theme {
    builtIn(.system(defaults: defaults))
  }

  /// The config's `[ui] theme`.
  public static func preferred(
    _ preference: ThemePreference, defaults: UserDefaults = .standard
  ) -> Theme {
    switch preference {
    case .auto: automatic(defaults: defaults)
    case .dark: .dark
    case .light: .light
    }
  }

  // Picked to stay distinct after FTXUI degrades them to the 256-colour palette (tested).
  public static let dark = Theme(
    name: "dark", appearance: .dark,
    colors: [
      .muted: .rgb(128, 128, 128),
      .accent: .rgb(95, 175, 255),
      .success: .rgb(135, 215, 135),
      .warning: .rgb(255, 215, 95),
      .danger: .rgb(255, 95, 95),
      .info: .rgb(95, 215, 215),
      .border: .rgb(88, 88, 88),
      .focus: .rgb(95, 175, 255),
      .selection: .rgb(0, 75, 135),
      .inactiveSelection: .rgb(58, 58, 58),
      .codeBackground: .rgb(38, 38, 38),
    ])

  public static let light = Theme(
    name: "light", appearance: .light,
    colors: [
      .muted: .rgb(118, 118, 118),
      .accent: .rgb(0, 95, 175),
      .success: .rgb(0, 135, 0),
      .warning: .rgb(175, 95, 0),
      .danger: .rgb(215, 0, 0),
      .info: .rgb(0, 135, 135),
      .border: .rgb(178, 178, 178),
      .focus: .rgb(0, 95, 175),
      .selection: .rgb(175, 215, 255),
      .inactiveSelection: .rgb(228, 228, 228),
      .codeBackground: .rgb(238, 238, 238),
    ])
}
