/// A dotted numeric version (`2.1.302`), for checking command-line tools in `vocoder doctor`.
public struct CLIVersion: Comparable, Sendable, CustomStringConvertible {
  public let components: [Int]

  public init?(_ text: String) {
    let parts = text.split(separator: ".").map { Int($0) }
    guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
    components = parts.compactMap { $0 }
  }

  /// The first word of `--version` output (`2.1.302 (Claude Code)`) that is a version.
  /// Leading words are skipped (`git version 2.50.1 (Apple Git-155)`).
  public init?(versionOutput: String) {
    let words = versionOutput.split(whereSeparator: \.isWhitespace)
    guard let version = words.lazy.compactMap({ CLIVersion(String($0)) }).first else {
      return nil
    }
    self = version
  }

  public var description: String { components.map(String.init).joined(separator: ".") }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    let (left, right) = padded(lhs, rhs)
    return left.lexicographicallyPrecedes(right)
  }

  /// `2.1` equals `2.1.0`.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    let (left, right) = padded(lhs, rhs)
    return left == right
  }

  private static func padded(_ lhs: Self, _ rhs: Self) -> ([Int], [Int]) {
    let count = max(lhs.components.count, rhs.components.count)
    let pad = { (version: Self) in
      version.components + Array(repeating: 0, count: count - version.components.count)
    }
    return (pad(lhs), pad(rhs))
  }
}
