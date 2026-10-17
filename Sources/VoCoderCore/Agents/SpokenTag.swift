/// The `<spoken>…</spoken>` summary VoCoder asks agents to end each reply with (DESIGN §4.4):
/// it's spoken aloud, and hidden from the transcript.
public enum SpokenTag {
  public static let open = "<spoken>"
  public static let close = "</spoken>"

  /// The text without its spoken tags (trailing whitespace trimmed), and the last summary.
  public static func extract(from text: String) -> (text: String, spoken: String?) {
    var visible = ""
    var spoken: String?
    var rest = Substring(text)
    while let start = rest.range(of: open) {
      visible += rest[..<start.lowerBound]
      let inner = rest[start.upperBound...]
      guard let end = inner.range(of: close) else {
        spoken = trimmed(inner)
        rest = ""
        break
      }
      spoken = trimmed(inner[..<end.lowerBound])
      rest = inner[end.upperBound...]
    }
    visible += rest
    while visible.last?.isWhitespace == true { visible.removeLast() }
    return (visible, spoken.flatMap { $0.isEmpty ? nil : $0 })
  }

  private static func trimmed(_ text: Substring) -> String {
    String(text.drop { $0.isWhitespace }.reversed().drop { $0.isWhitespace }.reversed())
  }
}

/// Removes spoken tags from streamed text, holding back a chunk's tail while it could still be
/// the start of a tag. One filter per text block.
public struct SpokenTagFilter: Sendable {
  private var pending = ""
  private var insideTag = false

  public init() {}

  /// The visible part of `chunk` that is certain by now.
  public mutating func feed(_ chunk: String) -> String {
    pending += chunk
    var output = ""
    while true {
      let tag = insideTag ? SpokenTag.close : SpokenTag.open
      if let range = pending.range(of: tag) {
        if !insideTag { output += pending[..<range.lowerBound] }
        pending = String(pending[range.upperBound...])
        insideTag.toggle()
        continue
      }
      let keep = Self.partialTagSuffix(of: pending, tag: tag)
      let cut = pending.index(pending.endIndex, offsetBy: -keep)
      if !insideTag { output += pending[..<cut] }
      pending = String(pending[cut...])
      return output
    }
  }

  /// What's still held back at the end of the block (a tag start that never completed).
  public mutating func finish() -> String {
    defer { pending = "" }
    return insideTag ? "" : pending
  }

  /// Length of the longest suffix of `text` that is a proper prefix of `tag`.
  private static func partialTagSuffix(of text: String, tag: String) -> Int {
    for length in stride(from: min(tag.count - 1, text.count), to: 0, by: -1)
    where text.hasSuffix(tag.prefix(length)) {
      return length
    }
    return 0
  }
}
