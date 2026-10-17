// Colours for views: concrete values, or theme roles resolved against the current theme.
import VoCoderUIBridge

/// The 16 ANSI colours, in terminal order.
public enum ANSIColor: Int, Sendable, CaseIterable {
  case black, red, green, yellow, blue, magenta, cyan, grayLight
  case grayDark, redLight, greenLight, yellowLight, blueLight, magentaLight, cyanLight, white
}

/// A colour as written in a view. Always ask for the precise colour: the renderer degrades it to
/// what the terminal supports.
public enum Color: Hashable, Sendable {
  case ansi(ANSIColor)
  case palette(UInt8)
  case rgb(UInt8, UInt8, UInt8)
  /// A semantic role, resolved against the theme when the view is rendered.
  case role(ThemeRole)

  public static let text = Color.role(.text)
  public static let muted = Color.role(.muted)
  public static let accent = Color.role(.accent)
  public static let success = Color.role(.success)
  public static let warning = Color.role(.warning)
  public static let danger = Color.role(.danger)
  public static let info = Color.role(.info)
  public static let border = Color.role(.border)
  public static let focus = Color.role(.focus)
  public static let selection = Color.role(.selection)
  public static let selectionText = Color.role(.selectionText)
  public static let inactiveSelection = Color.role(.inactiveSelection)
  public static let codeBackground = Color.role(.codeBackground)

  /// The bridge colour, or nil for the terminal's default (a role the theme leaves unset).
  func resolved(in theme: Theme) -> VCColor? {
    switch self {
    case .ansi(let color): .named(VCNamedColor(rawValue: color.rawValue) ?? .black)
    case .palette(let index): .palette256(index)
    case .rgb(let red, let green, let blue): .rgb(red, green, blue)
    case .role(let role):
      // Themes hold concrete colours only (see `Theme.init`), so this doesn't recurse further.
      theme[role]?.resolved(in: theme)
    }
  }
}
