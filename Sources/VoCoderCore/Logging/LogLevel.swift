/// Severity of a log entry, ordered from least to most severe.
public enum LogLevel: Int, Sendable, Comparable, CaseIterable {
  case debug, info, notice, error, fault

  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

  var label: String {
    switch self {
    case .debug: "DEBUG"
    case .info: "INFO"
    case .notice: "NOTICE"
    case .error: "ERROR"
    case .fault: "FAULT"
    }
  }
}
