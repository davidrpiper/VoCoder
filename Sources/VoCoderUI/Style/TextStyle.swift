import VoCoderUIBridge

public struct TextStyle: OptionSet, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }

  public static let bold = TextStyle(rawValue: VCTextStyle.bold.rawValue)
  public static let dim = TextStyle(rawValue: VCTextStyle.dim.rawValue)
  public static let italic = TextStyle(rawValue: VCTextStyle.italic.rawValue)
  public static let underlined = TextStyle(rawValue: VCTextStyle.underlined.rawValue)
  public static let inverted = TextStyle(rawValue: VCTextStyle.inverted.rawValue)
  public static let strikethrough = TextStyle(rawValue: VCTextStyle.strikethrough.rawValue)

  var bridged: VCTextStyle { VCTextStyle(rawValue: rawValue) }
}

public enum BorderStyle: Sendable {
  case light, rounded, heavy, double, dashed
  /// Takes a border's space but draws nothing (keeps layouts aligned with bordered siblings).
  case empty

  var bridged: VCBorderStyle {
    switch self {
    case .light: .light
    case .rounded: .rounded
    case .heavy: .heavy
    case .double: .double
    case .dashed: .dashed
    case .empty: .empty
    }
  }
}
